![cover render](/docs/cover.png)

# WebGPU raytracer
This project is a TypeScript/WebGPU implementation of a physically-based raytracer, containing a small demo scene of various materials.

## Features
Like many raytracers, this raytracer begins by spawning a set of rays (defined by an origin point and direction vector) based on the viewer's location and orientation. Each ray is then checked against all the geometry in the scene to determine what it strikes first. The colors of the ray and direction in which the ray is reflected or refracted is determined based on the material of the surface it intersects.

### Rendering modes
The UI provides 3 rendering options:
1. **After every sample (coherent)**. The output colors are rendered after each sample is complete. Techniques involving compaction/sorting/partitioning based on whether a ray is done processing and what material the ray bounced off of are used here. (This tends to perform the slowest.)
1. **After every sample**. The output colors are rendered after each sample is complete. No compaction is performed.
1. **After all samples**. The output colors are rendered only after all samples are complete. (This tends to perform the fastest, but may cause the GPU to hang and the render to be stopped prematurely.)

The difference in render time will often vary with the remaining features.

### Lens distortion
Instead of shooting rays out from a flat plane:

$$\text{direction} = \text{normalize}\left(\begin{bmatrix}\alpha \cdot x \\\ \alpha \cdot y \\\ -1\end{bmatrix}\right)$$

we simulate the rays based on the surface of a sphere instead. The center of the screen $(0, 0)$ is a pole of the sphere, and the distance $r$ from the center is proportional to the distance $\alpha \cdot r$ we walk along the sphere from the pole, at an angle based on the angle $\theta$ from the screen's +x-axis.

$$\text{direction} = \begin{bmatrix} \cos(\theta) & -\sin(\theta) & 0 \\\ \sin(\theta) & \cos(\theta) & 0 \\\ 0 & 0 & 1 \end{bmatrix}\begin{bmatrix}\sin(\alpha \cdot r) \\\ 0 \\\ -\cos(\alpha \cdot r)\end{bmatrix}, \text{ where } \theta = \tan^{-1}(y, x)$$

This allows us to use very wide FoV values without the extreme stretching near the edges that the plane projection has. This also has the effect of rendering rounded edges even where mesh edges may be straight.

### Material properties
Various types of materials are available in the scene:
1. **Diffuse, non-transmissive**. Rays encountering the surface are reflected in all directions up to 90° from the surface normal, using cosine weighting.
1. **Glossy, non-transmissive**. Rays encountering the surface are reflected across the surface normal.
1. **Diffuse, transmissive icosphere**. Rays encountering the surface are either:
    1. Reflected as if the surface was non-transmissive, with a probability based on Shlick's approximation of fresnel.
    1. Refracted in all directions up to 90° from the negative of the surface normal, using cosine weighting.
1. **Glossy, transmisive**. Rays encountering the surface are either:
    1. Reflected as if the surface was non-transmissive, with a probability based on Shlick's approximation of fresnel.
    1. Refracted 
1. **Emissive/environment**. Rays encountering the surface are terminated.

Each material type has a color associated with it. The final color of a ray is the product of all the colors of all the surfaces it encounters, or black if the ray is not terminated (i.e., does not encounter a light source) within the maximum number of bounces.

### Sampling, stochastic antialiasing
Antialiasing, or smoothing of edges, is performed by supersampling each pixel. Given a supersampling rate $n$, each pixel is divided into an $n \times n$ grid, and a random point in each grid cell is selected as the direction of the ray. If $m$ is the number of samples per grid cell, then the final number of samples is $n^2 \times m$. Colors for each pixel are written to an output buffer by progressively taking the average based on the current sample number.

|No supersampling, 64 samples / grid cell|$4 \times 4$ supersampling, 4 samples / grid cell|$8 \times 8$ supersampling, 1 sample / grid cell|
|-|-|-|
|![64x1, no overlays](/docs/antialiasing/64x1.png)|![4x4, no overlays](/docs/antialiasing/4x4.png)|![1x8, no overlays](/docs/antialiasing/1x8.png)|
|![64x1](/docs/antialiasing/64x1%20overlay.png)|![4x4](/docs/antialiasing/4x4%20overlay.png)|![1x8](/docs/antialiasing/1x8%20overlay.png)|
|0.437 s/frame|0.439 s/frame|0.443 s/frame|

### Depth of field
Depth of field is simulated by uniformly jittering the starting point of each ray within a disc aligned with the screen (correlated with aperture size), and then adjusting the ray direction based on the focus distance (correlated with focal length).

|No DoF|Default|Large aperture|Large focal length|Large focal length and aperture|
|-|-|-|-|-|
|![no dof, no overlays](/docs/dof/none.png)|![default, no overlays](/docs/default.png)|![large aperture, no overlays](/docs/dof/high%20radius.png)|![large focal length, no overlays](/docs/dof/high%20distance.png)|![large both, no overlays](/docs/dof/both%20high.png)|
|![no dof](/docs/dof/none%20overlay.png)|![default](/docs/default%20overlay.png)|![large aperture](/docs/dof/high%20radius%20overlay.png)|![large focal length](/docs/dof/high%20distance%20overlay.png)|![large both](/docs/dof/both%20high%20overlay.png)|
|0.438 s/frame|0.442 s/frame|0.443 s/frame|0.460 s/frame|0.547 s/frame|

### Environment mapping

### gLTF mesh and material loading

### Bounding box culling

### Terminated ray compaction/partioning

### Ray material sorting/partitioning

### Linear sRGB color blending
To achieve more realistic lighting, RGB arithmetic is done in linear sRGB space and then approximately converted to gamma sRGB by raising each component to the power of $\frac1{2.2}$ as a final pass in the fragment shader when drawing the results to the scren. The environment texture is converted in linear sRGB from gamma sRGB by raising its components to the power of $2.2$.


## Running this project
This is a Deno/Node.js application that builds to a static web app. If you have Deno installed, you can use `deno i` and `deno task dev` to run this project locally and `deno task build` or `deno task build:rel` to build it.

## Attributions
**Environment map**: [Minedump Flats](https://polyhaven.com/a/minedump_flats) by Dimitrios Savva and Jarod Guest

**Libraries**:
- **THREE.js**. gLTF loading
- **SvelteKit**. UI/reacitvity/routing
- **SASS**. CSS preprocessing
- **Vite**. Web app bundling and development environment