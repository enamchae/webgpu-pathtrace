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

$$\text{direction} = \operatorname{normalize}\left(\begin{bmatrix}\alpha \cdot x \\\ \alpha \cdot y \\\ -1\end{bmatrix}\right)$$

we simulate the rays based on the surface of a sphere instead. The center of the screen $(0, 0)$ is a pole of the sphere, and the distance $r$ from the center is proportional to the distance $\alpha \cdot r$ we walk along the sphere from the pole, at an angle based on the angle $\theta$ from the screen's +x-axis.

$$\text{direction} = \begin{bmatrix} \cos(\theta) & -\sin(\theta) & 0 \\\ \sin(\theta) & \cos(\theta) & 0 \\\ 0 & 0 & 1 \end{bmatrix}\begin{bmatrix}\sin(\alpha \cdot r) \\\ 0 \\\ -\cos(\alpha \cdot r)\end{bmatrix}, \text{ where } \theta = \tan^{-1}(y, x)$$

This allows us to use very wide FoV values without the extreme stretching near the edges that the plane projection has. This also has the effect of rendering rounded edges even where mesh edges may be straight.

### Diffuse reflection

### Glossy reflection

### Diffuse and glossy refraction

### Emission

### Stochastic antialiasing

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