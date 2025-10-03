const PI = 3.1415926;
const REV = 2 * PI;
const PI_2 = PI / 2;
const PI_4 = PI / 4;
const SQRT_1_3 = 1 / sqrt(3);

const SUPERSAMPLE_RATE = 16u;
const WORKGROUP_SIZE = 256u;
const N_MAX_BOUNCES = 8u;


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
    diffuse: vec4f,
    emissive: vec4f,
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
var<storage, read_write> stored: Stored;

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
    resolution: vec2u,
}

struct Stored {
    nth_pass: u32,
}

fn terminated_ray_with_col(linear_col: vec3f, index: u32, material_index: u32) -> Ray {
    return Ray(vec3f(0, 0, 0), vec3f(0, 0, 0), material_index, vec3f(0, 0, 0), index, linear_col, 1);
}


@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    if thread_index >= uniforms.resolution.x * uniforms.resolution.y { return; }


    let uv = get_square_centered_uv(thread_index);

    var avg_linear_col = vec3f(0, 0, 0);
    for (var nth_pass = 1u; nth_pass <= SUPERSAMPLE_RATE * SUPERSAMPLE_RATE; nth_pass++) {
        var ray = set_up_sample(uv, nth_pass, thread_index);
        var linear_col = vec3f(0, 0, 0);

        for (var depth = 0u; depth < N_MAX_BOUNCES; depth++) {
            if ray.terminated == 1 {
                linear_col = ray.linear_col;
                break;
            }
            
            ray = step_sample(ray);
        }
        
        avg_linear_col = mix(avg_linear_col, linear_col, 1 / f32(nth_pass));
    }
    output[thread_index] = avg_linear_col;
}

@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_begin_pass(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let thread_index = global_id.x;
    if thread_index >= uniforms.resolution.x * uniforms.resolution.y { return; }

    let uv = get_square_centered_uv(thread_index);
    rays[thread_index] = set_up_sample(uv, stored.nth_pass, thread_index);
    
    if thread_index == 0 {
        stored.nth_pass += 1;
    }
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
    output[ray.thread_index] = mix(output[ray.thread_index], linear_col, 1 / f32(stored.nth_pass));
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


@compute
@workgroup_size(WORKGROUP_SIZE)
fn comp_sort_intersections(
    @builtin(global_invocation_id) global_id: vec3u,
) {
    let n_intersections = uniforms.resolution.x * uniforms.resolution.y;
    let thread_index = global_id.x;


    // odd even sort

    var left_intersection: IntersectionResult;
    var right_intersection: IntersectionResult;

    var pair_index = thread_index * 2 + 1;
    if pair_index + 1 < n_intersections {
        left_intersection = intersections[pair_index];
        right_intersection = intersections[pair_index + 1];

        var should_swap = left_intersection.terminated > right_intersection.terminated;
        should_swap = should_swap || (left_intersection.terminated == right_intersection.terminated && left_intersection.found > right_intersection.found);
        should_swap = should_swap || (left_intersection.terminated == right_intersection.terminated && left_intersection.found == right_intersection.found && left_intersection.material_index > right_intersection.material_index);

        if should_swap {
            intersections[pair_index] = right_intersection;
            intersections[pair_index + 1] = left_intersection;
        }
    }

    storageBarrier();

    pair_index = thread_index * 2;
    if pair_index + 1 < n_intersections {
        left_intersection = intersections[pair_index];
        right_intersection = intersections[pair_index + 1];
        
        var should_swap = left_intersection.terminated > right_intersection.terminated;
        should_swap = should_swap || (left_intersection.terminated == right_intersection.terminated && left_intersection.found > right_intersection.found);
        should_swap = should_swap || (left_intersection.terminated == right_intersection.terminated && left_intersection.found == right_intersection.found && left_intersection.material_index > right_intersection.material_index);

        if should_swap {
            intersections[pair_index] = right_intersection;
            intersections[pair_index + 1] = left_intersection;
        }
    }
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

    // use Cramer's rule to solve for barycentric coordinates

    let coeffs_determinant = determinant(mat3x3(ba, ca, dir));
    if coeffs_determinant == 0 {
        return vec2f(INF, INF);
    }

    return vec2f(
        determinant(mat3x3(solution, ca, dir)) / coeffs_determinant,
        determinant(mat3x3(ba, solution, dir)) / coeffs_determinant,
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

fn intersect(origin: vec3f, dir: vec3f, thread_index: u32) -> IntersectionResult {
    var found = 0u;
    var closest_obj_index = 0u;
    var min_result = DistanceResult(vec3f(0, 0, 0), vec3f(0, 0, 0), INF);
    var closest_material_index = 0u;

    for (var i = 0u; i < arrayLength(&triangles); i++) {
        let triangle = triangles[i];
        let result = triangle_distance(triangle, origin, dir);

        if result.distance < min_result.distance {
            found = 1;
            closest_obj_index = i;
            min_result = result;
            closest_material_index = triangle.material_index;
        }
    }
    
    return IntersectionResult(min_result, closest_obj_index, closest_material_index, found, 0, thread_index);
}

fn xxhash32_3d(p: vec3u) -> u32 {
    let p2 = 2246822519u; let p3 = 3266489917u;
    let p4 = 668265263u; let p5 = 374761393u;
    var h32 =  p.z + p5 + p.x*p3;
    h32 = p4 * ((h32 << 17) | (h32 >> (32 - 17)));
    h32 += p.y * p3;
    h32 = p4 * ((h32 << 17) | (h32 >> (32 - 17)));
    h32 = p2 * (h32^(h32 >> 15));
    h32 = p3 * (h32^(h32 >> 13));
    return h32^(h32 >> 16);
}
fn rand33(f: vec3f) -> vec3f {
    let hash = f32(xxhash32_3d(bitcast<vec3u>(f)));
    
    return vec3f(hash, hash, hash) / f32(0xffffffff);
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
    let uniform_samples = rand33(seed);

    var new_normal: vec3f;
    if dot(dir, normal) > 0 {
        new_normal = -normal;
    } else {
        new_normal = normal;
    }

    let hemisphere_point = sample_cosine_weighted_hemisphere(uniform_samples.xy, new_normal);

    return hemisphere_point;
}

fn env(dir: vec3f) -> vec3f {
    return vec3f(0.3, 0.45, 0.5) * (2 * dir + 1);
    // return vec3f(0.97, 0.95, 1);
}

fn shade_ray(result: IntersectionResult, ray: Ray) -> Ray {
    if result.found == 0 {
        return terminated_ray_with_col(ray.linear_col * env(ray.dir), ray.thread_index, result.material_index);
    }

    let material = materials[result.material_index];
    if material.emissive.a > 0 {
        return terminated_ray_with_col(ray.linear_col * material.emissive.rgb, ray.thread_index, result.material_index);
    }


    let new_origin = result.intersection.point;
    // current_dir = reflect(current_dir, result.intersection.normal);
    let new_dir = diffuse_reflect(result.intersection.normal, ray.dir, ray.seed);

    return Ray(new_origin, new_dir, result.material_index, ray.seed, ray.thread_index, ray.linear_col * material.diffuse.rgb, 0);
}

fn step_sample(ray: Ray) -> Ray {
    let result = intersect(ray.origin, ray.dir, ray.thread_index);
    return shade_ray(result, ray);
}


fn set_up_sample(uv: vec2f, nth_pass: u32, index: u32) -> Ray {
    let uniform_samples = rand33(vec3f(uv, f32(nth_pass))).xy;


    let grid_index = nth_pass % (SUPERSAMPLE_RATE * SUPERSAMPLE_RATE);
    let grid_x = nth_pass % SUPERSAMPLE_RATE;
    let grid_y = nth_pass / SUPERSAMPLE_RATE;


    let adjusted_uv = uv + (vec2f(f32(grid_x), f32(grid_y)) - 0.5 + uniform_samples) / f32(SUPERSAMPLE_RATE) / (vec2f(uniforms.resolution) / 2);

    return Ray(vec3f(0, 0, 0), get_dir(adjusted_uv), 0, vec3f(adjusted_uv, f32(nth_pass)), index, vec3f(1, 1, 1), 0);
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