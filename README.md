# Material Aging CUDA Path Tracer

A real-time CUDA-based path tracer with physically-based material aging simulation. This project demonstrates dynamic aging processes of materials, including rust formation, wear patterns, oxidation, and surface deterioration in real-time.

## Features

- Real-time path tracing with CUDA acceleration
- Physical-based material aging simulation
- Interactive material parameter controls
- Multiple aging effects:
  - Rust formation
  - Surface wear and scratches
  - Metal oxidation
  - Dirt accumulation
- Cornell box scene with various material demonstrations
- Real-time parameter adjustment via ImGui interface

## Requirements

- CUDA Toolkit 12.0 or higher
- CMake 3.10 or higher
- X11 development libraries
- OpenGL
- GLFW3
- C++17 compatible compiler
- Linux operating system (tested on Fedora)

## Building

### Installing Dependencies (Fedora)

```bash
# Install required packages
sudo dnf install \
    cuda-toolkit \
    cmake \
    gcc-c++ \
    libX11-devel \
    mesa-libGL-devel \
    glfw-devel

# Verify CUDA installation
nvcc --version
```

### Building the Project

```bash
# Clone the repository
git clone https://github.com/yourusername/material-aging-pathtracer.git
cd material-aging-pathtracer

# Create build directory
mkdir build
cd build

# Configure and build
cmake ..
make -j$(nproc)
```

## Running

```bash
# From the build directory
./cuda_pathtracer/CUDAPathTracer
```

## Usage

The application provides an interactive window with ImGui controls for adjusting material aging parameters:

### Material Controls

#### Metallic Sphere
- Rust Amount: Controls the coverage of rust
- Rust Color Mix: Adjusts the blend between rust and base material
- Rust Roughness: Controls the surface roughness of rusted areas
- Wear Amount: Adjusts the amount of surface wear
- Wear Pattern Scale: Controls the scale of wear patterns
- Oxidation Amount: Adjusts the level of oxidation
- Dirt Amount: Controls dirt accumulation

#### Glossy Sphere
- Similar controls as metallic sphere but with different default parameters

### Camera Controls
- Mouse: Look around when captured
- WASD: Move camera
- Space/Shift: Move up/down
- ESC: Release mouse capture


## Performance

The path tracer is optimized for real-time performance on modern NVIDIA GPUs. Performance will vary based on:
- GPU capabilities
- Resolution
- Number of samples per pixel
- Scene complexity
- Aging effect parameters

## Technical Details

- CUDA-accelerated path tracing
- Physically based rendering (PBR)
- Real-time material aging simulation
- ImGui-based user interface
- GLFW window management
- OpenGL integration for display

## Contributing

Feel free to submit issues, fork the repository, and create pull requests for any improvements.

## Authors

Qervas - [GitHub](https://github.com/Qervas)

## Acknowledgments

- ImGui for the user interface
- NVIDIA for CUDA toolkit
- The path tracing community for various resources and inspiration
