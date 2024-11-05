#include "raytracer_kernel.cuh"
#include "Camera.cuh"
#include "Scene.cuh"
#include "Error.cuh"
#include "Material.cuh"
#include "Intersection.cuh"
#include "ScatterRecord.cuh"
#include <curand_kernel.h>
#include <math_constants.h>

// Define device constants
__constant__ GPUCamera d_camera;
__constant__ GPUSphere d_spheres[16];
__constant__ GPUPlane d_planes[16];
__constant__ int d_num_spheres;
__constant__ int d_num_planes;

// Device intersection structure
struct GPUIntersection {
    float3 point;
    float3 normal;
    float distance;
    float3 color;
    bool frontFace;
    float3 emission;
    bool hit;

    // conversion constructor from Intersection_t
    __device__ GPUIntersection& operator=(const Intersection_t& isect) {
        point = make_float3(isect.point.x, isect.point.y, isect.point.z);
        normal = make_float3(isect.normal.x, isect.normal.y, isect.normal.z);
        distance = isect.distance;
        color = make_float3(isect.color.r, isect.color.g, isect.color.b);
        frontFace = isect.frontFace;
        emission = make_float3(isect.emission.r, isect.emission.g, isect.emission.b);
        hit = isect.hit;
        return *this;
    }
};

// Device helper functions
__device__ Intersection_t intersectSphere(const Ray_t& ray, const GPUSphere& sphere) {
    Intersection_t isect;
    isect.hit = false;
    
    Vec3f_t sphere_center = Vec3f_t::fromFloat3(sphere.center);
    Vec3f_t oc = ray.origin - sphere_center;
    
    float a = 1.0f;  // Optimized since ray direction is normalized
    float half_b = dot(oc, ray.direction);
    float c = dot(oc, oc) - sphere.radius * sphere.radius;
    float discriminant = half_b * half_b - a * c;
    
    if (discriminant < 0) return isect;
    
    float sqrtd = sqrtf(discriminant);
    float root = (-half_b - sqrtd) / a;
    
    if (!ray.isValidDistance(root)) {
        root = (-half_b + sqrtd) / a;
        if (!ray.isValidDistance(root)) return isect;
    }
    
    isect.hit = true;
    isect.distance = root;
    isect.point = ray.at(root);
    isect.normal = (isect.point - sphere_center) / sphere.radius;
    isect.material = sphere.material;
    isect.setFaceNormal(ray, isect.normal);
    
    if (sphere.is_emissive) {
        isect.emission = Color_t::fromFloat3(sphere.emission);
    }
    
    return isect;
}

__device__ Intersection_t intersectPlane(const Ray_t& ray, const GPUPlane& plane) {
    Intersection_t isect;
    isect.hit = false;
    
    Vec3f_t plane_normal = Vec3f_t::fromFloat3(plane.normal);
    Vec3f_t plane_point = Vec3f_t::fromFloat3(plane.point);
    
    float denom = dot(plane_normal, ray.direction);
    
    if (fabsf(denom) < 1e-6f) return isect;
    
    float t = dot(plane_point - ray.origin, plane_normal) / denom;
    
    if (!ray.isValidDistance(t)) return isect;
    
    isect.hit = true;
    isect.distance = t;
    isect.point = ray.at(t);
    isect.normal = plane_normal;
    isect.material = plane.material;
    isect.setFaceNormal(ray, plane_normal);
    
    return isect;
}

__device__ Intersection_t intersectScene(const Ray_t& ray) {
    Intersection_t closest_hit;
    closest_hit.hit = false;
    float closest_dist = FLOAT_MAX;

    // Check sphere intersections
    for (int i = 0; i < d_num_spheres; i++) {
        Intersection_t sphere_isect = intersectSphere(ray, d_spheres[i]);
        if (sphere_isect.hit && sphere_isect.distance < closest_dist) {
            closest_dist = sphere_isect.distance;
            closest_hit = sphere_isect;
        }
    }

    // Check plane intersections
    for (int i = 0; i < d_num_planes; i++) {
        Intersection_t plane_isect = intersectPlane(ray, d_planes[i]);
        if (plane_isect.hit && plane_isect.distance < closest_dist) {
            closest_dist = plane_isect.distance;
            closest_hit = plane_isect;
        }
    }

    return closest_hit;
}

__device__ inline float3 operator*(const float3& a, float b) {
    return make_float3(a.x * b, a.y * b, a.z * b);
}

__device__ inline float3 operator+(const float3& a, const float3& b) {
    return make_float3(a.x + b.x, a.y + b.y, a.z + b.z);
}

__device__ inline float3 operator*(const float3& a, const float3& b) {
    return make_float3(a.x * b.x, a.y * b.y, a.z * b.z);
}

__device__ inline float length(const float3& a) {
	return sqrtf(a.x * a.x + a.y * a.y + a.z * a.z);
}

__device__ Color_t traceRay(Ray_t ray, curandState* rand_state, int max_depth) {
    Color_t final_color(0.0f);
    Color_t throughput(1.0f);
    
    for (int depth = 0; depth < max_depth; depth++) {
        Intersection_t isect = intersectScene(ray);
        if (!isect.hit) break;  // Ray missed everything, add background color (black)
        
        // Get emitted light
        final_color += throughput * isect.material->emitted(ray, isect);
        
        // Handle scattering
        ScatterRecord_t srec;
        if (!isect.material->scatter(ray, isect, srec, rand_state)) {
            break;
        }
        
        if (srec.is_specular) {
            throughput *= srec.attenuation;
            ray = srec.scattered_ray;
            continue;
        }
        
        // Update ray for next iteration
        ray = srec.scattered_ray;
        
        // Update throughput
        Color_t brdf = srec.attenuation * isect.material->scatteringPdf(ray, isect, srec.scattered_ray);
        throughput *= brdf * (1.0f / srec.pdf);
        
        // Russian roulette termination
        if (depth > 3) {
            float p = fmaxf(throughput.r, fmaxf(throughput.g, throughput.b));
            if (curand_uniform(rand_state) > p) {
                break;
            }
            throughput *= 1.0f / p;
        }
    }
    
    return final_color;
}

__device__ Ray_t generateCameraRay(float u, float v) {
    // Get camera data from constant memory
    const float aspect_ratio = static_cast<float>(d_camera.width) / d_camera.height;
    const float viewport_height = 2.0f * tanf(d_camera.fov * 0.5f);
    const float viewport_width = aspect_ratio * viewport_height;

    // Calculate viewport vectors
    Vec3f_t origin = Vec3f_t::fromFloat3(d_camera.origin);
    Vec3f_t forward = Vec3f_t::fromFloat3(d_camera.forward);
    Vec3f_t right = Vec3f_t::fromFloat3(d_camera.right);
    Vec3f_t up = Vec3f_t::fromFloat3(d_camera.up);

    // Calculate the point on the viewport
    float x_offset = (2.0f * u - 1.0f) * viewport_width * 0.5f;
    float y_offset = (2.0f * v - 1.0f) * viewport_height * 0.5f;
    
    Vec3f_t ray_direction = forward + right * x_offset + up * y_offset;
    ray_direction = ray_direction.normalized();

    return Ray_t(origin, ray_direction, Ray_t::Type::PRIMARY);
}

__device__ void initRand(curandState* rand_state, uint32_t seed) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int idy = blockIdx.y * blockDim.y + threadIdx.y;
    int offset = idy * gridDim.x * blockDim.x + idx;
    curand_init(seed + offset, 0, 0, rand_state);
}

__global__ void renderKernel(float4* output, uint32_t width, uint32_t height, uint32_t frame_count) {
    const int x = blockIdx.x * blockDim.x + threadIdx.x;
    const int y = blockIdx.y * blockDim.y + threadIdx.y;
    
    if (x >= width || y >= height) return;
    
    const int pixel_index = y * width + x;
    
    // Initialize random state
    curandState rand_state;
    initRand(&rand_state, frame_count * width * height + pixel_index);
    
    // Calculate UV coordinates with jittering
    const float u = (x + curand_uniform(&rand_state)) / static_cast<float>(width);
    const float v = (y + curand_uniform(&rand_state)) / static_cast<float>(height);
    
    // Generate camera ray
    Ray_t ray = generateCameraRay(u, v);
    
    // Trace ray and accumulate color
    Color_t pixel_color = traceRay(ray, &rand_state, 50);  // Max depth of 50
    
    // Accumulate samples if frame_count > 0
    if (frame_count > 0) {
        float4 prev_color = output[pixel_index];
        float t = 1.0f / (frame_count + 1);
        pixel_color = pixel_color * t + Color_t(prev_color.x, prev_color.y, prev_color.z) * (1.0f - t);
    }
    
    // Write final color
    output[pixel_index] = make_float4(pixel_color.r, pixel_color.g, pixel_color.b, 1.0f);
}

// initialization function
void initializeGPUData(const Camera_t& camera, const Scene_t* d_scene) {
    // Validate scene pointer
    if (!d_scene) {
        throw std::runtime_error("Scene pointer is null in initializeGPUData");
    }

    // Copy scene structure from device to host
    Scene_t h_scene;
    CUDA_CHECK(cudaMemcpy(&h_scene, d_scene, sizeof(Scene_t), cudaMemcpyDeviceToHost));

    // Setup camera data
    GPUCamera h_camera;
    h_camera.origin = make_float3(camera.getPosition().x, camera.getPosition().y, camera.getPosition().z);
    h_camera.forward = make_float3(camera.getForward().x, camera.getForward().y, camera.getForward().z);
    h_camera.right = make_float3(camera.getRight().x, camera.getRight().y, camera.getRight().z);
    h_camera.up = make_float3(camera.getUp().x, camera.getUp().y, camera.getUp().z);
    h_camera.fov = camera.getSettings().fov * M_PI / 180.0f;
    h_camera.width = camera.getWidth();
    h_camera.height = camera.getHeight();

    // Copy camera data to GPU
    cudaMemcpyToSymbol(d_camera, &h_camera, sizeof(GPUCamera));

    // Setup scene objects
    std::vector<GPUSphere> h_spheres;
    std::vector<GPUPlane> h_planes;

    // Validate implicit object count and pointer
    if (h_scene.implicit_object_count <= 0 || !h_scene.d_implicit_objects) {
        // If there are no objects, just set the counts to 0 and return
        int num_spheres = 0;
        int num_planes = 0;
        cudaMemcpyToSymbol(d_num_spheres, &num_spheres, sizeof(int));
        cudaMemcpyToSymbol(d_num_planes, &num_planes, sizeof(int));
        return;
    }

    // Create host array of implicit objects
    ImplicitObject_t** h_implicit_objects = nullptr;
    try {
        h_implicit_objects = new ImplicitObject_t*[h_scene.implicit_object_count];
        
        // Copy device pointers to host
        CUDA_CHECK(cudaMemcpy(h_implicit_objects, h_scene.d_implicit_objects, 
                             h_scene.implicit_object_count * sizeof(ImplicitObject_t*), 
                             cudaMemcpyDeviceToHost));

        // Convert implicit objects to GPU format
        for (uint32_t i = 0; i < h_scene.implicit_object_count; ++i) {
            const ImplicitObject_t* obj = h_implicit_objects[i];
            
            // Check if object is a sphere by calling isSphere()
            if (obj->isSphere()) {
                const Sphere_t* sphere = static_cast<const Sphere_t*>(obj);
                GPUSphere gpu_sphere;
                gpu_sphere.center = make_float3(sphere->getCenter().x, sphere->getCenter().y, sphere->getCenter().z);
                gpu_sphere.radius = sphere->getRadius();
                gpu_sphere.material = sphere->getMaterial();
                gpu_sphere.is_emissive = sphere->isEmissive();
                if (sphere->isEmissive()) {
                    Color_t emission = sphere->getEmissionColor() * sphere->getEmissionStrength();
                    gpu_sphere.emission = make_float3(emission.r, emission.g, emission.b);
                } else {
                    gpu_sphere.emission = make_float3(0.0f, 0.0f, 0.0f);
                }
                h_spheres.push_back(gpu_sphere);
            }
        }

        // plane handling
        for (uint32_t i = 0; i < h_scene.implicit_object_count; ++i) {
            const ImplicitObject_t* obj = h_implicit_objects[i];
            
            if (obj->isPlane()) {
                const Plane_t* plane = static_cast<const Plane_t*>(obj);
                GPUPlane gpu_plane;
                gpu_plane.point = make_float3(plane->getPoint().x, plane->getPoint().y, plane->getPoint().z);
                gpu_plane.normal = make_float3(plane->getNormal().x, plane->getNormal().y, plane->getNormal().z);
                gpu_plane.material = plane->getMaterial();
                h_planes.push_back(gpu_plane);
            }
        }

        // Cleanup host array
        delete[] h_implicit_objects;

        // Copy scene data to GPU
        int num_spheres = static_cast<int>(h_spheres.size());
        cudaMemcpyToSymbol(d_num_spheres, &num_spheres, sizeof(int));
        if (num_spheres > 0) {
            cudaMemcpyToSymbol(d_spheres, h_spheres.data(), h_spheres.size() * sizeof(GPUSphere));
        }

        int num_planes = static_cast<int>(h_planes.size());
        cudaMemcpyToSymbol(d_num_planes, &num_planes, sizeof(int));
        if (num_planes > 0) {
            cudaMemcpyToSymbol(d_planes, h_planes.data(), h_planes.size() * sizeof(GPUPlane));
        }

    } catch (const std::exception& e) {
        if (h_implicit_objects) {
            delete[] h_implicit_objects;
        }
        throw;
    }
}

// this function to handle kernel launch
extern "C" void launchRenderKernel(float4* output, uint32_t width, uint32_t height, uint32_t frame_count, dim3 grid, dim3 block) {
    renderKernel<<<grid, block>>>(output, width, height, frame_count);
}

