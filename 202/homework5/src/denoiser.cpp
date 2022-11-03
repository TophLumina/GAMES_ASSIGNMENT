#include "denoiser.h"

Denoiser::Denoiser() : m_useTemportal(false) {}

void Denoiser::Reprojection(const FrameInfo &frameInfo) {
    int height = m_accColor.m_height;
    int width = m_accColor.m_width;
    Matrix4x4 preWorldToScreen =
        m_preFrameInfo.m_matrix[m_preFrameInfo.m_matrix.size() - 1];
    Matrix4x4 preWorldToCamera =
        m_preFrameInfo.m_matrix[m_preFrameInfo.m_matrix.size() - 2];
#pragma omp parallel for
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            // TODO: Reproject
            m_valid(x, y) = false;
            m_misc(x, y) = Float3(0.f);

            Float3 pre_pos = frameInfo.m_position(x, y);
            float pre_id = (int)frameInfo.m_id(x, y);
            
            if (pre_id >= 0.f) {
                Matrix4x4 back_proj = Inverse(frameInfo.m_matrix[pre_id]);
                back_proj = m_preFrameInfo.m_matrix[pre_id] * back_proj;
                back_proj = preWorldToScreen * back_proj;

                pre_pos = back_proj(pre_pos, Float3::EType::Point);


                if (pre_pos.x >= 0 && pre_pos.x < width && pre_pos.y >= 0 && pre_pos.y < height) {
                    if ((int)m_preFrameInfo.m_id(pre_pos.x,pre_pos.y) == (int)pre_id) {
                        m_valid(x, y) = true;
                        m_misc(x, y) = m_accColor(pre_pos.x, pre_pos.y);
                    }
                }
            }
        }
    }
    std::swap(m_misc, m_accColor);
}

void Denoiser::TemporalAccumulation(const Buffer2D<Float3> &curFilteredColor) {
    int height = m_accColor.m_height;
    int width = m_accColor.m_width;
    int kernelRadius = 3;
#pragma omp parallel for
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            // TODO: Temporal clamp
            Float3 color = m_accColor(x, y);
            // TODO: Exponential moving average
            float alpha = 1.0f;

            if (m_valid(x ,y)) {
                Float3 ave_col(0.f);

                for (int i = -3; i <= 3; i++) {
                    for (int j = -3; j <= 3; j++) {
                        int coord_x = x + i;
                        int coord_y = y + j;

                        if (coord_x >= 0 && coord_x < width && coord_y >= 0 && coord_y < height) {
                            ave_col += curFilteredColor(coord_x, coord_y);
                        }
                        else {
                            ave_col += curFilteredColor(x, y);
                        }
                    }
                }
                ave_col /= 49.f;

                Float3 sigma_col(0.f);
                for (int i = -3; i <= 3; i++) {
                    for (int j = -3; j <= 3; j++) {
                        int coord_x = x + i;
                        int coord_y = y + j;

                        if (coord_x >= 0 && coord_x < width && coord_y >= 0 && coord_y < height) {
                            sigma_col +=
                                Sqr(AbsSum(curFilteredColor(coord_x, coord_y), ave_col));
                        }
                    }
                }
                sigma_col /= 49.f;

                color = Clamp(color, ave_col - sigma_col, ave_col + sigma_col);
                alpha = m_alpha;
            }

            m_misc(x, y) = Lerp(color, curFilteredColor(x, y), alpha);
        }
    }
    std::swap(m_misc, m_accColor);
}

Buffer2D<Float3> Denoiser::Filter(const FrameInfo &frameInfo) {
    int height = frameInfo.m_beauty.m_height;
    int width = frameInfo.m_beauty.m_width;
    Buffer2D<Float3> filteredImage = CreateBuffer2D<Float3>(width, height);
    int kernelRadius = 16;
#pragma omp parallel for
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            // TODO: Joint bilateral filter

            Float3 tmp_result(0.f);
            float weight = 0.f;

            for (int i = -kernelRadius; i <= kernelRadius; ++i) {
                for (int j = -kernelRadius; j <= kernelRadius; ++j) {
                    int coord_x = x + i;
                    int coord_y = y + j;

                    if (coord_x >= 0 && coord_x <= width && coord_y >= 0 && coord_y <= height && i != 0  && j != 0) {
                        float meta_pos =
                            SqrLength(Float3(i, j, 0.f)) / (2.f * Sqr(m_sigmaCoord));
                        float meta_col =
                            SqrDistance(frameInfo.m_beauty(x, y),
                                        frameInfo.m_beauty(coord_x, coord_y)) /
                            (2.f * Sqr(m_sigmaColor));
                        float meta_norm =
                            Sqr(SafeAcos(Dot(frameInfo.m_normal(x, y),
                                             frameInfo.m_normal(coord_x, coord_y)))) /
                            (2.f * Sqr(m_sigmaNormal));
                        float meta_plane =
                            Sqr(std::max(
                                Dot(frameInfo.m_normal(x, y),
                                    (frameInfo.m_position(coord_x, coord_y) -
                                     frameInfo.m_position(
                                         x, y)) / // RuntimeERR::Dvide by ZERO ? CHECK PLZ.
                                        std::max(Length(frameInfo.m_position(coord_x,
                                                                             coord_y) -
                                                        frameInfo.m_position(x, y)),
                                                 0.000001f)), // 2 different pixels have the exact same world_coords? How is it even possible?
                                                 // Oh I got it. If 2 pixels all fail to find world_coord, maybe they will share a same coords.
                                0.f)) /
                            (2.f * Sqr(m_sigmaPlane));

                        float factor =
                            expf(-meta_pos - meta_col - meta_norm - meta_plane);

                        filteredImage(x, y) += frameInfo.m_beauty(coord_x, coord_y) * factor;
                        weight += factor;
                    }
                    else {
                        filteredImage(x, y) += frameInfo.m_beauty(x, y);
                        weight += 1.f;
                    }
                }
            }
            // filteredImage(x, y) = frameInfo.m_beauty(x, y);

            filteredImage(x, y) /= weight;
        }
    }
    return filteredImage;
}

void Denoiser::Init(const FrameInfo &frameInfo, const Buffer2D<Float3> &filteredColor) {
    m_accColor.Copy(filteredColor);
    int height = m_accColor.m_height;
    int width = m_accColor.m_width;
    m_misc = CreateBuffer2D<Float3>(width, height);
    m_valid = CreateBuffer2D<bool>(width, height);
}

void Denoiser::Maintain(const FrameInfo &frameInfo) { m_preFrameInfo = frameInfo; }

Buffer2D<Float3> Denoiser::ProcessFrame(const FrameInfo &frameInfo) {
    // Filter current frame
    Buffer2D<Float3> filteredColor;
    filteredColor = Filter(frameInfo);

    // Reproject previous frame color to current
    if (m_useTemportal) {
        Reprojection(frameInfo);
        TemporalAccumulation(filteredColor);
    } else {
        Init(frameInfo, filteredColor);
    }

    // Maintain
    Maintain(frameInfo);
    if (!m_useTemportal) {
        m_useTemportal = true;
    }
    return m_accColor;
}
