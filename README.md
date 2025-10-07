![cover render](/docs/cover.png)

# WebGPU raytracer
This project is a pure JS/WebGPU implementation of a physically-based raytracer, containing a small demo scene of various materials.

## Features
Like many raytracers, this raytracer begins by spawning a set of rays (defined by an origin point and direction vector) based on the viewer's location and orientation. Each ray is then checked against all the geometry in the scene to determine what it strikes first. The colors of the ray and direction in which the ray is reflected or refracted is determined based on the material of the surface it intersects.

### Lens distortion
Instead of shooting rays out from a flat plane:

$$\text{direction} = \operatorname{normalize}\left(\begin{bmatrix}\alpha \cdot x \\\ \alpha \cdot y \\\ -1\end{bmatrix}\right)$$

we simulate the rays based on the surface of a sphere instead. The center of the screen $(0, 0)$ is a pole of the sphere, and the distance $r$ from the center is proportional to the distance $\alpha \cdot r$ we walk along the sphere from the pole, at an angle based on the angle $\theta$ from the screen's +x-axis.

$$\text{direction} = \begin{bmatrix} \cos(\theta) & -\sin(\theta) & 0 \\\ \sin(\theta) & \cos(\theta) & 0 \\\ 0 & 0 & 1 \end{bmatrix}\begin{bmatrix}\sin(\alpha \cdot r) \\\ 0 \\\ -\cos(\alpha \cdot r)\end{bmatrix}, \text{ where } \theta = \tan^{-1}(y, x)$$

This produces rounded edges even where mesh edges may be straight.

### Diffuse reflection

### Glossy reflection

### Diffuse and glossy refraction

### Emission

### Stochastic antialiasing

### Depth of field

### Environment mapping

### gLTF mesh and material loading

### Bounding box culling

### Terminated ray compaction/partioning

### Ray material sorting/partitioning


## Running this project
This is a Deno/Node.js application that builds to a static web app. If you have Deno installed, you can use `deno i` and `deno task dev` to run this project locally and `deno task build` or `deno task build:rel` to build it.

## Attributions
**Environment map**: [Minedump Flats](https://polyhaven.com/a/minedump_flats) by Dimitrios Savva and Jarod Guest

**Libraries**:
- **THREE.js**. gLTF loading
- **SvelteKit**. UI/reacitvity/routing
- **SASS**. CSS preprocessing
- **Vite**. Web app bundling and development environment