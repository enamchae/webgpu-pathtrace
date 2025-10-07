const PI = 3.1415926;
const REV = 2 * PI;
const PI_2 = PI / 2;
const PI_4 = PI / 4;
const SQRT_1_3 = 1 / sqrt(3);

const WORKGROUP_SIZE = 256u;


struct Triangle {
    a: vec3f,
    material_index: u32,
    b: vec3f,
    c: vec3f,
}

@group(0)
@binding(0)
var<storage, read> triangles: array<Triangle>;


struct Material {
    diffuse: vec3f,
    transmision: f32,
    emissive: vec4f,
    roughness: f32,
}

@group(0)
@binding(1)
var<storage, read> materials: array<Material>;

@group(0)
@binding(2)
var<uniform> uniforms: Uniforms;

@group(0)
@binding(3)
var<storage, read_write> output: array<vec3f>;

@group(0)
@binding(4)
var<storage, read_write> intersections: array<IntersectionResult>;

@group(0)
@binding(5)
var<storage, read_write> rays: array<Ray>;

@group(0)
@binding(6)
var<storage, read_write> compact_bools: array<vec2u>;

@group(0)
@binding(7)
var<storage, read_write> compact_out: array<Ray>;

@group(0)
@binding(8)
var<storage, read_write> radix_bools: array<vec4u>;

@group(0)
@binding(9)
var<storage, read_write> material_out: array<IntersectionResult>;

@group(0)
@binding(10)
var env_texture: texture_2d<f32>;

@group(0)
@binding(11)
var<storage, read> bounding_boxes: array<BoundingBox>;

struct BoundingBox {
    min: vec3f,
    max: vec3f,
    triangle_index: u32,
}


struct Ray {
    origin: vec3f,
    dir: vec3f,
    last_material_index: u32,
    seed: vec3f,
    thread_index: u32,
    linear_col: vec3f,
    terminated: u32, // cannot use bool in storage
}

struct Uniforms {
    // 0
    resolution: vec2u, // 8

    nth_pass: u32, // 12

    supersample_rate: u32, // 16
    n_samples_per_grid_cell: u32, // 20
    n_max_bounces: u32, // 24
    dof_radius: f32, // 28
    dof_distance: f32, // 32
    
    camera_transform: mat4x4f, // 96

    compact_sweep_step: u32, // 100
    radix_shift: u32, // 104
}

struct Stored {
    nth_pass: u32,
}

fn terminated_ray_with_col(linear_col: vec3f, index: u32, material_index: u32) -> Ray {
    return Ray(vec3f(0, 0, 0), vec3f(0, 0, 0), material_index, vec3f(0, 0, 0), index, linear_col, 1);
}


@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_full(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    if thread_index >= uniforms.resolution.x * uniforms.resolution.y { return; }


    let uv = get_square_centered_uv(thread_index);

    var avg_linear_col = vec3f(0, 0, 0);
    for (var nth_pass = 1u; nth_pass <= uniforms.supersample_rate * uniforms.supersample_rate * uniforms.n_samples_per_grid_cell; nth_pass++) {
        var ray = set_up_sample(uv, nth_pass, thread_index);
        var linear_col = vec3f(0, 0, 0);

        for (var depth = 0u; depth < uniforms.n_max_bounces; depth++) {
            if ray.terminated == 1 {
                linear_col = ray.linear_col;
                break;
            }
            
            let result = intersect(ray.origin, ray.dir, ray.thread_index);
            ray = shade_ray(result, ray);
        }
        
        avg_linear_col = mix(avg_linear_col, linear_col, 1 / f32(nth_pass));
    }
    output[thread_index] = avg_linear_col;
}

@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_single_pass(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    if thread_index >= uniforms.resolution.x * uniforms.resolution.y { return; }

    let nth_pass = uniforms.nth_pass;


    let uv = get_square_centered_uv(thread_index);

    var ray = set_up_sample(uv, nth_pass, thread_index);
    var linear_col = vec3f(0, 0, 0);

    for (var depth = 0u; depth < uniforms.n_max_bounces; depth++) {
        if ray.terminated == 1 {
            linear_col = ray.linear_col;
            break;
        }
        
        let result = intersect(ray.origin, ray.dir, ray.thread_index);
        ray = shade_ray(result, ray);
    }
    
    output[thread_index] = mix(output[thread_index], linear_col, 1 / f32(nth_pass + 1));
}

@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_begin_pass(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    if thread_index >= uniforms.resolution.x * uniforms.resolution.y { return; }

    let uv = get_square_centered_uv(thread_index);
    rays[thread_index] = set_up_sample(uv, uniforms.nth_pass, thread_index);
}

@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_intersect(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    if thread_index >= uniforms.resolution.x * uniforms.resolution.y { return; }
    
    let ray = rays[thread_index];
    if ray.terminated == 1 {
        intersections[thread_index] = IntersectionResult(
            DistanceResult(vec3f(0, 0, 0), vec3f(0, 0, 0), INF),
            0, 0, 0, 0, thread_index,
        );
        return;
    }

    intersections[thread_index] = intersect(ray.origin, ray.dir, thread_index);
}

@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_shade(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    if thread_index >= uniforms.resolution.x * uniforms.resolution.y { return; }
    
    let result = intersections[thread_index];
    let ray = rays[result.thread_index];
    if ray.terminated == 1 { return; }


    rays[result.thread_index] = shade_ray(result, ray);
}

@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_finish_pass(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    if thread_index >= uniforms.resolution.x * uniforms.resolution.y { return; }

    let ray = rays[thread_index];
    let linear_col = ray.linear_col * f32(ray.terminated);
    output[ray.thread_index] = mix(output[ray.thread_index], linear_col, 1 / f32(uniforms.nth_pass + 1));
}

fn shift_material_index(material_index: u32) -> u32 {
    return (material_index >> (uniforms.radix_shift * 2)) & 0x3;
}

fn one_hot_4(n: u32) -> vec4u {
    return select(
        select(
            select(
                vec4u(1, 0, 0, 0),
                vec4u(0, 1, 0, 0),
                n == 1,
            ),
            vec4u(0, 0, 1, 0),
            n == 2,
        ),
        vec4u(0, 0, 0, 1),
        n == 3,
    );
}

@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_set_material_bools(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    if thread_index >= arrayLength(&radix_bools) { return; }

    if thread_index >= arrayLength(&intersections) {
        radix_bools[thread_index] = vec4u(0, 0, 0, 0);
        return;
    }

    let material_index_bits = shift_material_index(intersections[thread_index].material_index);

    radix_bools[thread_index] = one_hot_4(material_index_bits);
}

@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_material_upsweep(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    let index_right = (thread_index + 1) * uniforms.compact_sweep_step - 1;
    if index_right >= arrayLength(&radix_bools) { return; }

    let index_left = index_right - uniforms.compact_sweep_step / 2;

    radix_bools[index_right] += radix_bools[index_left];
}

@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_material_downsweep(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    let index_right = (thread_index + 1) * uniforms.compact_sweep_step - 1;
    if index_right >= arrayLength(&radix_bools) { return; }

    let index_left = index_right - uniforms.compact_sweep_step / 2;

    let right = radix_bools[index_right];
    radix_bools[index_right] += radix_bools[index_left];
    radix_bools[index_left] = right;
}

@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_material_scatter(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    if thread_index >= arrayLength(&intersections) { return; }

    let intersection = intersections[thread_index];
    let material_index_bits = shift_material_index(intersection.material_index);

    let current = radix_bools[thread_index];
    
    let totals = radix_bools[arrayLength(&radix_bools) - 1];
    
    // edge case where the last element needs to be included
    let last_element_contribution = select(
        vec4u(0, 0, 0, 0),
        one_hot_4(shift_material_index(intersections[arrayLength(&intersections) - 1].material_index)),
        arrayLength(&intersections) == arrayLength(&radix_bools)
    );
    let final_totals = totals + last_element_contribution;

    // starting positions for each material index
    let group_0_start = 0u;
    let group_1_start = final_totals.x;
    let group_2_start = group_1_start + final_totals.y;
    let group_3_start = group_2_start + final_totals.z;

    let intersection_index = select(
        select(
            select(
                group_0_start + current.x,
                group_1_start + current.y,
                material_index_bits == 1,
            ),
            group_2_start + current.z,
            material_index_bits == 2,
        ),
        group_3_start + current.w,
        material_index_bits == 3,
    );

    material_out[intersection_index] = intersection;
}

@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_material_copy_back(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    if thread_index >= arrayLength(&intersections) { return; }

    intersections[thread_index] = material_out[thread_index];
}


@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_set_terminated_bools(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    if thread_index >= arrayLength(&compact_bools) { return; }

    if thread_index >= arrayLength(&rays) {
        compact_bools[thread_index] = vec2u(0, 0);
        return;
    }

    let ray = rays[thread_index];

    compact_bools[thread_index] = vec2u(ray.terminated, 1 - ray.terminated);
}

@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_terminated_upsweep(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    let index_right = (thread_index + 1) * uniforms.compact_sweep_step - 1;
    if index_right >= arrayLength(&compact_bools) { return; }

    let index_left = index_right - uniforms.compact_sweep_step / 2;

    compact_bools[index_right] += compact_bools[index_left];
}

@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_terminated_downsweep(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    let index_right = (thread_index + 1) * uniforms.compact_sweep_step - 1;
    if index_right >= arrayLength(&compact_bools) { return; }

    let index_left = index_right - uniforms.compact_sweep_step / 2;

    let right = compact_bools[index_right];
    compact_bools[index_right] += compact_bools[index_left];
    compact_bools[index_left] = right;
}

@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_terminated_scatter(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    if thread_index >= arrayLength(&rays) { return; }

    let ray = rays[thread_index];
    

    let total_terminated = compact_bools[arrayLength(&compact_bools) - 1].x;
    let last_ray_terminated = select(0u, 1u, arrayLength(&rays) == arrayLength(&compact_bools) && rays[arrayLength(&rays) - 1].terminated == 1);
    let final_total_terminated = total_terminated + last_ray_terminated;


    let ray_index = select(
        compact_bools[thread_index].y + final_total_terminated,
        compact_bools[thread_index].x,
        ray.terminated == 1,
    );

    compact_out[ray_index] = ray;
}

@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_terminated_copy_back(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    if thread_index >= arrayLength(&rays) { return; }

    rays[thread_index] = compact_out[thread_index];
}

fn get_aspect_vec() -> vec2f {
    if uniforms.resolution.y > uniforms.resolution.x {
        return vec2f(1, f32(uniforms.resolution.y) / f32(uniforms.resolution.x));
    } else {
        return vec2f(f32(uniforms.resolution.x) / f32(uniforms.resolution.y), 1);
    }
}

fn get_square_centered_uv(thread_index: u32) -> vec2f {
    let y = thread_index / uniforms.resolution.x;
    let x = thread_index - y * uniforms.resolution.x;

    var uv = vec2f(f32(x), f32(y)) / vec2f(uniforms.resolution) * 2 - 1;
    uv.y *= -1;

    return uv * get_aspect_vec();
}


struct VertexOut {
    @builtin(position) position: vec4f,
    @location(0) uv: vec2f,
}

@vertex
fn vert(
    @location(0) position: vec4f,
) -> VertexOut {
    var output: VertexOut;

    output.position = position;
    output.uv = position.xy;

    return output;
}

fn project_to_screen(pt: vec3f) -> vec2f {
    return pt.xy / pt.z;
}

fn triangle_normal(triangle: Triangle) -> vec3f {
    return normalize(cross(triangle.b - triangle.a, triangle.c - triangle.a));
}

fn triangle_intersect_t(triangle: Triangle, origin: vec3f, dir: vec3f, normal: vec3f) -> f32 {
    return dot(triangle.a - origin, normal) / dot(dir, normal);
}

const EPSILON: f32 = 1e-4;
const INF: f32 = pow(2, 126);

fn triangle_intersect_barycentric(triangle: Triangle, intersection_pt: vec3f, dir: vec3f) -> vec2f {
    let ba = triangle.b - triangle.a;
    let ca = triangle.c - triangle.a;
    let solution = intersection_pt - triangle.a;

    let dummy = cross(ba, ca);

    // use Cramer's rule to solve for barycentric coordinates

    let coeffs_determinant = determinant(mat3x3(ba, ca, dummy));
    if coeffs_determinant == 0 {
        return vec2f(INF, INF);
    }

    return vec2f(
        determinant(mat3x3(solution, ca, dummy)) / coeffs_determinant,
        determinant(mat3x3(ba, solution, dummy)) / coeffs_determinant,
    );
}

struct DistanceResult {
    normal: vec3f,
    point: vec3f,
    distance: f32,
}

fn triangle_distance(triangle: Triangle, origin: vec3f, dir: vec3f) -> DistanceResult {
    let normal = triangle_normal(triangle);

    let t = triangle_intersect_t(triangle, origin, dir, normal);
    if t < EPSILON {
        return DistanceResult(normal, vec3f(0, 0, 0), INF);
    }

    let intersection_pt = origin + dir * t;

    let barycentric = triangle_intersect_barycentric(triangle, intersection_pt, dir);
    if barycentric.x < 0 || barycentric.y < 0 || barycentric.x + barycentric.y > 1 {
        return DistanceResult(normal, intersection_pt, INF);
    }

    return DistanceResult(normal, intersection_pt, t);
}

struct IntersectionResult {
    intersection: DistanceResult,
    closest_obj_index: u32,
    material_index: u32,
    found: u32,
    terminated: u32,
    thread_index: u32,
}

// slab method
fn ray_intersects_bounding_box(box: BoundingBox, origin: vec3f, dir: vec3f) -> bool {
    let t1 = (box.min - origin) / dir;
    let t2 = (box.max - origin) / dir;
    
    let mins = min(t1, t2);
    let maxes = max(t1, t2);
    
    let max_of_mins = max(max(mins.x, mins.y), mins.z);
    let min_of_maxes = min(min(maxes.x, maxes.y), maxes.z);
    
    return min_of_maxes >= max_of_mins && min_of_maxes >= EPSILON;
}


fn intersect(origin: vec3f, dir: vec3f, thread_index: u32) -> IntersectionResult {
    var found = 0u;
    var closest_obj_index = 0u;
    var min_result = DistanceResult(vec3f(0, 0, 0), vec3f(0, 0, 0), INF);
    var closest_material_index = 0u;

    let n_bounding_boxes = arrayLength(&bounding_boxes);
    for (var i = 0u; i < n_bounding_boxes; i++) {
        let box = bounding_boxes[i];
        if !ray_intersects_bounding_box(box, origin, dir) { continue; }

        let start = box.triangle_index;
        var end = arrayLength(&triangles);
        if i != n_bounding_boxes - 1 {
            end = bounding_boxes[i + 1].triangle_index;
        }

        for (var j = 0u; j < arrayLength(&triangles); j++) {
            let triangle = triangles[j];
            let result = triangle_distance(triangle, origin, dir);

            if result.distance < min_result.distance {
                found = 1;
                closest_obj_index = j;
                min_result = result;
                closest_material_index = triangle.material_index;
            }
        }
    }
    
    return IntersectionResult(min_result, closest_obj_index, closest_material_index, found, 0, thread_index);
}

// https://xxhash.com/
fn xxhash_3d(p: vec3u) -> u32 {
    const p2 = 2246822519u;
    const p3 = 3266489917u;
    const p4 = 668265263u;
    const p5 = 374761393u;

    var h32 = p.z + p5 + p.x * p3;
    h32 = p4 * ((h32 << 17) | (h32 >> (32 - 17)));
    h32 += p.y * p3;
    h32 = p4 * ((h32 << 17) | (h32 >> (32 - 17)));
    h32 = p2 * (h32^(h32 >> 15));
    h32 = p3 * (h32^(h32 >> 13));
    return h32^(h32 >> 16);
}

fn rand_3d(f: vec3f) -> vec3f {
    let hash = f32(xxhash_3d(bitcast<vec3u>(f)));
    
    return vec3f(hash, hash, hash) / f32(0xFFFFFFFF);
}

fn sample_cosine_weighted_hemisphere(uniform_samples: vec2f, normal: vec3f) -> vec3f {
    // sample a point on the unit sphere's top half
    let z = uniform_samples.x;
    let band_radius = sqrt(1 - z * z);
    let angle = uniform_samples.y * REV;

    // construct a coordinate system achievable by rotating some world axis to the given normal
    var basis_comparator: vec3f;
    if abs(normal.x) < SQRT_1_3 {
        basis_comparator = vec3f(1, 0, 0);
    }
    else if abs(normal.y) < SQRT_1_3 {
        basis_comparator = vec3f(0, 1, 0);
    }
    else {
        basis_comparator = vec3f(0, 0, 1);
    }

    // these just need to be orthonormal to the normal
    let cross1 = normalize(cross(normal, basis_comparator));
    let cross2 = normalize(cross(normal, cross1));

    return mat3x3(cross1, cross2, normal) * vec3f(band_radius * cos(angle), band_radius * sin(angle), z);
}

fn diffuse_reflect(normal: vec3f, dir: vec3f, seed: vec3f) -> vec3f {
    let uniform_samples = rand_3d(seed);

    let hemisphere_point = sample_cosine_weighted_hemisphere(uniform_samples.xy, normal * -sign(dot(dir, normal)));

    return hemisphere_point;
}

fn env(dir: vec3f) -> vec3f {
    let u = atan2(dir.z, dir.x) / REV + 0.5;
    let v = 1 - acos(dir.y) / PI;
    
    let dim = textureDimensions(env_texture);
    let uv = vec2i(
        i32(u * f32(dim.x)) % i32(dim.x),
        i32(v * f32(dim.y)) % i32(dim.y),
    );
    
    let col = textureLoad(env_texture, uv, 0).rgb;
    return vec3f(
        pow(col.x, 2.2),
        pow(col.y, 2.2),
        pow(col.z, 2.2),
    );
}

fn fresnel(normal: vec3f, dir: vec3f, ior_1: f32, ior_2: f32) -> f32 {
    let sqrt_r0 = (ior_1 - ior_2) / (ior_1 + ior_2);
    let r0 = sqrt_r0 * sqrt_r0;

    let one_cos = 1 - dot(normal, dir);
    let one_cos_2 = one_cos * one_cos;

    return r0 + (1 - r0) * one_cos_2 * one_cos_2 * one_cos;
}

fn shade_ray(result: IntersectionResult, ray: Ray) -> Ray {
    if result.found == 0 {
        return terminated_ray_with_col(ray.linear_col * env(ray.dir), ray.thread_index, result.material_index);
    }

    let uniform_samples = rand_3d(ray.seed + 0.1);
    let material = materials[result.material_index];
    if material.emissive.a > 0 {
        return terminated_ray_with_col(ray.linear_col * material.emissive.rgb, ray.thread_index, result.material_index);
    }


    let ior_1 = 1.;
    let ior_2 = 1.5;

    let is_entering_material = dot(ray.dir, result.intersection.normal) < 0;
    let effective_normal = result.intersection.normal * select(-1., 1., is_entering_material);
    
    let reflective_diffuse_dir = diffuse_reflect(result.intersection.normal, ray.dir, ray.seed);

    let reflectance = fresnel(effective_normal, ray.dir, ior_1, ior_2);

    let new_origin = result.intersection.point;
    var new_dir: vec3f;
    if uniform_samples.x > reflectance || uniform_samples.y < material.transmision {
        let reflected_dir = reflect(ray.dir, result.intersection.normal);

        new_dir = select(reflective_diffuse_dir, reflected_dir, material.roughness < 0.5);
    } else {
        let ior_ratio = select(ior_1 / ior_2, ior_2 / ior_1, is_entering_material);
        let refracted_dir = refract(ray.dir, effective_normal, ior_ratio);
        
        new_dir = select(-reflective_diffuse_dir, normalize(refracted_dir), material.roughness < 0.5 && length(refracted_dir) > 0);
    }

    return Ray(new_origin, new_dir, result.material_index, ray.seed, ray.thread_index, ray.linear_col * material.diffuse.rgb, 0);
}

fn set_up_sample(uv: vec2f, nth_pass: u32, index: u32) -> Ray {
    let supersample_grid_jitter = rand_3d(vec3f(uv, f32(nth_pass))).xy;
    let dof_jitter_params = rand_3d(vec3f(uv, f32(nth_pass)) - 5.9).xy; // (r^2, theta)

    let dof_radius = sqrt(dof_jitter_params.x) * uniforms.dof_radius;
    let dof_angle = REV * dof_jitter_params.y;

    let dof_jittered_origin = vec3f(dof_radius * vec2f(cos(dof_angle), sin(dof_angle)), 0);


    let grid_index = nth_pass % (uniforms.supersample_rate * uniforms.supersample_rate);
    let grid_x = nth_pass % uniforms.supersample_rate;
    let grid_y = nth_pass / uniforms.supersample_rate;


    let adjusted_uv = uv + (vec2f(f32(grid_x), f32(grid_y)) - 0.5 + supersample_grid_jitter) / f32(uniforms.supersample_rate) / (vec2f(uniforms.resolution) / 2);
    let orig_dir = get_dir(adjusted_uv);
    let seed = vec3f(adjusted_uv, f32(nth_pass));
    
    let dof_jittered_dir = normalize(orig_dir * f32(uniforms.dof_distance) - dof_jittered_origin);


    let final_dir = (uniforms.camera_transform * vec4f(dof_jittered_dir, 0)).xyz;
    let final_origin = (uniforms.camera_transform * vec4f(dof_jittered_origin, 1)).xyz;

    return Ray(final_origin, final_dir, 0, seed, index, vec3f(1, 1, 1), 0);
}

fn get_dir(uv: vec2f) -> vec3f {
    // let dir = normalize(vec3(data.uv, -1));

    // for lens-like rendering, the UV radius determines the angle change along a sphere
    // the UV angle is just used to rotate the direction vector into place, using the matrix
    let sphere_angle = length(uv) * 0.5;
    let uv_angle = atan2(uv.y, uv.x);

    let dir = mat3x3(
        cos(uv_angle), -sin(uv_angle), 0,
        sin(uv_angle), cos(uv_angle), 0,
        0, 0, 1,
    ) * vec3f(sin(sphere_angle), 0, -cos(sphere_angle));

    return dir;
}

@fragment
fn frag_from_output(
    data: VertexOut,
) -> @location(0) vec4f {
    let linear_col = output[u32(data.position.y) * uniforms.resolution.x + u32(data.position.x)];

    return vec4f(
        pow(linear_col.x, 1 / 2.2),
        pow(linear_col.y, 1 / 2.2),
        pow(linear_col.z, 1 / 2.2),
        1,
    );
}