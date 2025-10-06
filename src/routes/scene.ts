import {GLTFLoader} from "three/addons/loaders/GLTFLoader.js";
import { Material, Matrix4, MeshPhysicalMaterial, Object3D, Scene, Vector3 } from "three";


const traverseChildren = (scene: Object3D, fn: (child: Object3D) => void) => {
    fn(scene);

    for (const child of scene.children) {
        traverseChildren(child, fn);
    }
};

const vec = (array: Float32Array, mat: Matrix4) => {
    const vec3 = new Vector3(array[0], array[1], array[2]).applyMatrix4(mat);
    return [vec3.x, -vec3.y, vec3.z];
};

export const loadGltfScene = async (url: string) => {
    const gltf: {scene: Scene} = await new Promise((resolve, reject) => new GLTFLoader().load(url, resolve));

    let nTriBytes = 0;
    let nMaterialBytes = 0;
    let nBoundingBoxBytes = 0;

    const materialMap = new Map<MeshPhysicalMaterial, number>();

    traverseChildren(gltf.scene, child => {
        if (!Object.hasOwn(child, "geometry")) return;
        nTriBytes += child.geometry.index.array.length / 3 * 48;
        
        if (!materialMap.has(child.material)) {
            materialMap.set(child.material, materialMap.size);
            nMaterialBytes += 48;
        }

        nBoundingBoxBytes += 32;
    });

    const triangles = new ArrayBuffer(nTriBytes);
    let triOffset = 0;

    const boundingBoxes = new ArrayBuffer(nBoundingBoxBytes);
    let boundingBoxOffset = 0;

    traverseChildren(gltf.scene, child => {
        if (!Object.hasOwn(child, "geometry")) return;


        const boxTriangleIndex = triOffset / 48;
        const boxMin = [Infinity, Infinity, Infinity];
        const boxMax = [-Infinity, -Infinity, -Infinity];


        const pos = child.geometry.attributes.position.array;
        const index = child.geometry.index.array;

        for (let i = 0; i < index.length; i += 3) {
            const v0 = vec(pos.slice(3 * index[i], 3 * index[i] + 3), child.matrix);
            const v1 = vec(pos.slice(3 * index[i + 1], 3 * index[i + 1] + 3), child.matrix);
            const v2 = vec(pos.slice(3 * index[i + 2], 3 * index[i + 2] + 3), child.matrix);

            new Float32Array(triangles, triOffset).set(v0);
            new Float32Array(triangles, triOffset + 16).set(v1);
            new Float32Array(triangles, triOffset + 32).set(v2);
            new Uint32Array(triangles, triOffset + 12).set([materialMap.get(child.material)!]);

            boxMin[0] = Math.min(boxMin[0], v0[0], v1[0], v2[0]);
            boxMin[1] = Math.min(boxMin[1], v0[1], v1[1], v2[1]);
            boxMin[2] = Math.min(boxMin[2], v0[2], v1[2], v2[2]);
            boxMax[0] = Math.max(boxMax[0], v0[0], v1[0], v2[0]);
            boxMax[1] = Math.max(boxMax[1], v0[1], v1[1], v2[1]);
            boxMax[2] = Math.max(boxMax[2], v0[2], v1[2], v2[2]);

            triOffset += 48;
        }

        new Float32Array(boundingBoxes, boundingBoxOffset).set([
            boxMin[0], boxMin[1], boxMin[2], 0,
            boxMax[0], boxMax[1], boxMax[2],
        ]);
        new Uint32Array(boundingBoxes, boundingBoxOffset + 28).set([boxTriangleIndex]);

        boundingBoxOffset += 32;
    });

    const materials = new ArrayBuffer(nMaterialBytes);
    for (const [material, i] of materialMap) {
        new Float32Array(materials, i * 48).set([
            material.color.r,
            material.color.g,
            material.color.b,
            Object.hasOwn(material, "_transmission") ? 1 - material._transmission : 1,

            material.emissive.r * material.emissiveIntensity,
            material.emissive.g * material.emissiveIntensity,
            material.emissive.b * material.emissiveIntensity,
            [material.emissiveIntensity, material.emissive.r, material.emissive.g, material.emissive.b].every(c => c > 0) ? 1 : 0,

            material.roughness,
            0,
            0,
            0,
        ]);
    }
    
        
    // const quads = [
    //     new Quad(
    //         new Vec3(1, 1, -2),
    //         new Vec3(1, -1, -2),
    //         new Vec3(1, -1, -4),
    //         new Vec3(1, 1, -4),
    //         1,
    //     ),

    //     new Quad(
    //         new Vec3(-1, 1, -2),
    //         new Vec3(1, 1, -2),
    //         new Vec3(1, 1, -4),
    //         new Vec3(-1, 1, -6),
    //     ),

    //     new Quad(
    //         new Vec3(-1, -1, -2),
    //         new Vec3(-1, 1, -2),
    //         new Vec3(-1, 1, -6),
    //         new Vec3(-1, -1, -6),
    //         2,
    //     ),

    //     new Quad(
    //         new Vec3(1, -1, -2),
    //         new Vec3(-1, -1, -2),
    //         new Vec3(-1, -1, -6),
    //         new Vec3(1, -1, -4),
    //         3,
    //     ),

    //     new Quad(
    //         new Vec3(1, 1, -4),
    //         new Vec3(-1, 1, -6),
    //         new Vec3(-1, -1, -6),
    //         new Vec3(1, -1, -4),
    //     ),

    //     // new Quad(
    //     //     new Vec3(0.75, 0.75, -4),
    //     //     new Vec3(-0.25, 0.75, -4),
    //     //     new Vec3(-0.25, -0.25, -4),
    //     //     new Vec3(0.75, -0.25, -4),
    //     //     [0, 0, 0, 1],
    //     //     [1, 1, 1, 1],
    //     // ),

    //     new Quad(
    //         new Vec3(0.5, -0.95, -1),
    //         new Vec3(-0.5, -0.95, -1),
    //         new Vec3(-0.5, -0.95, -6),
    //         new Vec3(0.5, -0.95, -6),
    //         4,
    //     ),

    //     new Quad(
    //         new Vec3(0.5, 0.3, -2),
    //         new Vec3(-0.5, 0.3, -2),
    //         new Vec3(-0.5, 0.3, -6),
    //         new Vec3(0.5, 0.3, -6),
    //     ),
    // ];

    // const triangles2 = new ArrayBuffer(quads.length * 96);
    // for (const [i, quad] of quads.entries()) {
    //     quad.writeTris(triangles2, i);
    // }

    return {
        boundingBoxes,
        triangles,
        materials,
    };
};