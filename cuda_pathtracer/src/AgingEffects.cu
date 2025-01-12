#include "AgingEffects.cuh"

__device__ float hash(float n) {
    float x = sinf(n) * 43758.5453f;
    return x - floorf(x);
}

__device__ float noise(const Point3f_t& point) {
    Point3f_t p(floorf(point.x), floorf(point.y), floorf(point.z));

    float x = point.x - p.x;
    float y = point.y - p.y;
    float z = point.z - p.z;

    p.x = hash(p.x);
    p.y = hash(p.y);
    p.z = hash(p.z);

    x = x * x * (3.0f - 2.0f * x);
    y = y * y * (3.0f - 2.0f * y);
    z = z * z * (3.0f - 2.0f * z);

    return hash(p.x + p.y * 57.0f + p.z * 113.0f);
}

__device__ Color_t AgingEffects::applyRustEffect(
    const Color_t& base_color,
    const Point3f_t& point,
    const RustParameters& params,
    float noise_value)
{
    // Generate rust pattern
    float pattern = noise(point * params.pattern_scale);
    float rust_amount = pattern * params.oxidation_level;

    // Modify surface properties based on rust
    Color_t rusted_color = lerp(base_color, params.rust_color, rust_amount);

    // Add roughness variation
    float roughness_factor = 1.0f + params.surface_roughness * rust_amount;
    rusted_color *= (1.0f / roughness_factor);

    return rusted_color;
}

__device__ Color_t AgingEffects::applyPaintAging(
    const Color_t& base_color,
    const Point3f_t& point,
    const PaintAgingParameters& params,
    float noise_value)
{
    // Generate crack pattern
    float crack_pattern = noise(point * (1.0f + params.crack_density * 10.0f));

    // Calculate peeling effect
    float peel_threshold = 1.0f - params.peeling_amount;
    float peel_factor = (noise_value > peel_threshold) ? 1.0f : 0.0f;

    // Apply weathering
    Color_t aged_color = base_color * (1.0f - params.weathering * 0.3f);

    // Combine effects
    Color_t final_color = lerp(aged_color, params.underlay_color, peel_factor);

    // Add cracks
    if (crack_pattern < params.crack_density * 0.2f) {
        final_color *= 0.7f;
    }

    return final_color;
}
