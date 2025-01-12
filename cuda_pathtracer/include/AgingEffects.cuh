#pragma once

#include "Vec3.cuh"
#include "Color.cuh"

struct RustParameters {
    float oxidation_level{0.0f};    // 0-1: Level of rust coverage
    float surface_roughness{0.0f};   // 0-1: How rough the rusted surface is
    float pattern_scale{1.0f};       // Scale of rust patterns
    float padding;
    Color_t rust_color{0.6f, 0.2f, 0.1f}; // Base color of rust
};

struct PaintAgingParameters {
    float peeling_amount{0.0f};      // 0-1: Amount of paint peeling
    float crack_density{0.0f};       // 0-1: Density of cracks
    float weathering{0.0f};          // 0-1: General weathering/fading
    float padding;
    Color_t underlay_color{0.3f};    // Color under the paint
};

class AgingEffects {
public:
    static __device__ Color_t applyRustEffect(
        const Color_t& base_color,
        const Point3f_t& point,
        const RustParameters& params,
        float noise_value);

    static __device__ Color_t applyPaintAging(
        const Color_t& base_color,
        const Point3f_t& point,
        const PaintAgingParameters& params,
        float noise_value);
};
