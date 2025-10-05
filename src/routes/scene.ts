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

    console.log(gltf);
    
    let nTriBytes = 0;
    let nMaterialBytes = 0;

    const materialMap = new Map<MeshPhysicalMaterial, number>();

    traverseChildren(gltf.scene, child => {
        if (!Object.hasOwn(child, "geometry")) return;
        nTriBytes += child.geometry.index.array.length / 3 * 48;
        
        if (!materialMap.has(child.material)) {
            materialMap.set(child.material, materialMap.size);
            nMaterialBytes += 48;
        }
    });

    const triangles = new ArrayBuffer(nTriBytes);
    let triOffset = 0;
    traverseChildren(gltf.scene, child => {
        if (!Object.hasOwn(child, "geometry")) return;

        const pos = child.geometry.attributes.position.array;
        const index = child.geometry.index.array;


        for (let i = 0; i < index.length; i += 3) {
            new Float32Array(triangles, triOffset).set(vec(pos.slice(3 * index[i], 3 * index[i] + 3), child.matrix));
            new Float32Array(triangles, triOffset + 16).set(vec(pos.slice(3 * index[i + 1], 3 * index[i + 1] + 3), child.matrix));
            new Float32Array(triangles, triOffset + 32).set(vec(pos.slice(3 * index[i + 2], 3 * index[i + 2] + 3), child.matrix));
            new Uint32Array(triangles, triOffset + 12).set([materialMap.get(child.material)!]);

            triOffset += 48;
        }
    });

    const materials = new ArrayBuffer(nMaterialBytes);
    for (const [material, i] of materialMap) {
        new Float32Array(materials, i * 48).set([
            material.color.r, material.color.g, material.color.b, Object.hasOwn(material, "_transmission") ? 1 - material._transmission : 1,
            material.emissive.r, material.emissive.g, material.emissive.b, 0,
            material.roughness, 0, 0, 0,
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
        triangles,
        materials,
    };
};