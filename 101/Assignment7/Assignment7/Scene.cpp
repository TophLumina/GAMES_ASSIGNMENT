//
// Created by Göksu Güvendiren on 2019-05-14.
//

#include "Scene.hpp"

void Scene::buildBVH()
{
    printf(" - Generating BVH...\n\n");
    this->bvh = new BVHAccel(objects, 1, BVHAccel::SplitMethod::NAIVE);
}

Intersection Scene::intersect(const Ray &ray) const
{
    return this->bvh->Intersect(ray);
}

void Scene::sampleLight(Intersection &pos, float &pdf) const
{
    float emit_area_sum = 0;
    for (uint32_t k = 0; k < objects.size(); ++k)
    {
        if (objects[k]->hasEmit())
        {
            emit_area_sum += objects[k]->getArea();
        }
    }
    float hit_pos = get_random_float() * emit_area_sum;
    emit_area_sum = 0;
    for (uint32_t k = 0; k < objects.size(); ++k)
    {
        if (objects[k]->hasEmit())
        {
            emit_area_sum += objects[k]->getArea();
            if (hit_pos <= emit_area_sum)
            {
                objects[k]->Sample(pos, pdf);
                break;
            }
        }
    }
}

bool Scene::trace(
    const Ray &ray,
    const std::vector<Object *> &objects,
    float &tNear, uint32_t &index, Object **hitObject)
{
    *hitObject = nullptr;
    for (uint32_t k = 0; k < objects.size(); ++k)
    {
        float tNearK = kInfinity;
        uint32_t indexK;
        Vector2f uvK;
        if (objects[k]->intersect(ray, tNearK, indexK) && tNearK < tNear)
        {
            *hitObject = objects[k];
            tNear = tNearK;
            index = indexK;
        }
    }

    return (*hitObject != nullptr);
}

// Implementation of Path Tracing
Vector3f Scene::castRay(const Ray &ray, int depth) const
{
    // TO DO Implement Path Tracing Algorithm here

    Intersection hit_inter = intersect(ray);
    if (hit_inter.happened == false)
        return Vector3f(0.f);

    if (hit_inter.m->hasEmission())
        return Vector3f(1.f);

    float pdf_light;
    Vector3f dir_lightfrom = normalize(-ray.direction);
    Vector3f hit_pos = hit_inter.coords;
    Vector3f hit_normal = normalize(hit_inter.normal);

    // Sampleing all lights in the scene, and changing the coord, normal and emit of the Intersection given.
    Intersection hit_light;
    sampleLight(hit_light, pdf_light);

    Vector3f light_pos = hit_light.coords;
    Vector3f emit = hit_light.emit;
    Vector3f dir_hit_2_light = normalize(light_pos - hit_pos);
    Vector3f light_normal = normalize(hit_light.normal);

    Vector3f L_dir(0.f);
    float distance_visibility = (intersect(Ray(hit_pos, dir_hit_2_light)).coords - light_pos).norm();

    // if the ray isn't blocked on its way to the light then caculate the L_dir.
    if (distance_visibility < EPSILON)
        L_dir = emit * hit_inter.m->eval(dir_lightfrom, dir_hit_2_light, hit_normal) * dotProduct(dir_hit_2_light, hit_normal) * dotProduct(-dir_hit_2_light, light_normal) / powf((light_pos - hit_pos).norm(), 2.f) / pdf_light;

    Vector3f L_indir(0.f);
    // if we fortunatyly survive the RussianRoulette then we should continue.
    if (get_random_float() < RussianRoulette)
    {
        Vector3f dir_out = hit_inter.m->sample(dir_lightfrom, hit_normal);
        // reclusive call the Raycasting func to get L_indir.

        L_indir = castRay(Ray(hit_pos, dir_out), depth) * hit_inter.m->eval(dir_out, dir_lightfrom, hit_normal) * dotProduct(dir_out, hit_normal) / hit_inter.m->pdf(dir_out, dir_lightfrom, hit_normal) / RussianRoulette;
    }
    return L_dir + L_indir;
}