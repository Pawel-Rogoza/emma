import {readFile,writeFile} from 'node:fs/promises';
import {makeGeometry} from '../src/relief.js';
import {morphNames} from '../src/relief.js';
import {poseAt} from '../src/animation.js';
const g=makeGeometry(),chunks=[],views=[],accessors=[];let offset=0;
function view(data){const b=Buffer.from(data.buffer??data,data.byteOffset??0,data.byteLength??data.length);const i=views.length;views.push({buffer:0,byteOffset:offset,byteLength:b.length});chunks.push(b);const pad=(4-b.length%4)%4;if(pad)chunks.push(Buffer.alloc(pad));offset+=b.length+pad;return i;}
function accessor(a,type,componentType,min,max){const i=accessors.length;accessors.push({bufferView:view(a),componentType,count:a.length/({VEC3:3,VEC2:2,VEC4:4,SCALAR:1}[type]),type,...(min?{min,max}:{})});return i;}
const baseMin=[Infinity,Infinity,Infinity],baseMax=[-Infinity,-Infinity,-Infinity];
g.attributes.position.array.forEach((v,i)=>{baseMin[i%3]=Math.min(baseMin[i%3],v);baseMax[i%3]=Math.max(baseMax[i%3],v);});
const pos=accessor(g.attributes.position.array,'VEC3',5126,baseMin,baseMax);
const normal=accessor(g.attributes.normal.array,'VEC3',5126);
// glTF texture coordinates use top-left origin.
const uv=g.attributes.uv.array.slice();for(let i=1;i<uv.length;i+=2)uv[i]=1-uv[i];
const tex=accessor(uv,'VEC2',5126),indices=accessor(g.index.array,'SCALAR',5123);
const png=await readFile(new URL('../public/emma-avatar.png',import.meta.url));const img=view(png);
const times=accessor(new Float32Array([0,1,2,3,4]),'SCALAR',5126,[0],[4]);
const rotations=accessor(new Float32Array([0,0,0,1,0,.006,0,Math.sqrt(1-.006**2),0,0,0,1,0,-.006,0,Math.sqrt(1-.006**2),0,0,0,1]),'VEC4',5126);
const json={asset:{version:'2.0',generator:'Emma portrait relief prototype',extras:{limitation:'Shallow photo-textured relief, not a full volumetric dog or rigged head.'}},scene:0,scenes:[{nodes:[0]}],nodes:[{name:'EmmaPortraitRelief',mesh:0}],meshes:[{primitives:[{attributes:{POSITION:pos,NORMAL:normal,TEXCOORD_0:tex},indices,material:0}]}],materials:[{name:'Accepted portrait / baked lighting',pbrMetallicRoughness:{baseColorTexture:{index:0},metallicFactor:0,roughnessFactor:1},extensions:{KHR_materials_unlit:{}}}],extensionsUsed:['KHR_materials_unlit'],textures:[{source:0}],images:[{bufferView:img,mimeType:'image/png'}],animations:[{name:'idle',samplers:[{input:times,output:rotations,interpolation:'LINEAR'}],channels:[{sampler:0,target:{node:0,path:'rotation'}}]}],buffers:[{byteLength:offset}],bufferViews:views,accessors};
json.materials[0].alphaMode='BLEND';
json.meshes[0].primitives[0].targets=g.morphAttributes.position.map(a=>{
 const min=[Infinity,Infinity,Infinity],max=[-Infinity,-Infinity,-Infinity];
 for(let i=0;i<a.array.length;i++){const axis=i%3;min[axis]=Math.min(min[axis],a.array[i]);max[axis]=Math.max(max[axis],a.array[i]);}
 return {POSITION:accessor(a.array,'VEC3',5126,min,max)};
});
json.meshes[0].weights=morphNames.map(()=>0);
for(const id of [pos,normal,tex,...json.meshes[0].primitives[0].targets.map(t=>t.POSITION)])views[accessors[id].bufferView].target=34962;
views[accessors[indices].bufferView].target=34963;
json.meshes[0].extras={targetNames:morphNames};
json.animations=['waiting','listening','thinking','speaking','interrupted'].map(state=>{
 const ts=[],weights=[],qs=[];
 for(let f=0;f<=234;f++){
  const t=f/30,p=poseAt(t,state,state==='speaking'?.5:0);
  // Ease into the initial pose during the final 0.6 s; no one-frame loop snap.
  const start=poseAt(0,state,state==='speaking'?.5:0),u=Math.max(0,(t-7.2)/.6),blend=u*u*(3-2*u);
  for(const axis of ['x','y','z'])p[axis]+=(start[axis]-p[axis])*blend;
  p.morphs=p.morphs.map((v,i)=>v+(start.morphs[i]-v)*blend);
  ts.push(t);weights.push(...p.morphs);
  // XYZ Euler to quaternion, same convention as Three.js mesh rotations.
  const c1=Math.cos(p.x/2),c2=Math.cos(p.y/2),c3=Math.cos(p.z/2),s1=Math.sin(p.x/2),s2=Math.sin(p.y/2),s3=Math.sin(p.z/2);
  qs.push(s1*c2*c3+c1*s2*s3,c1*s2*c3-s1*c2*s3,c1*c2*s3+s1*s2*c3,c1*c2*c3-s1*s2*s3);
 }
 // Seamless wrap, including morph weights.
 weights.splice(weights.length-5,5,...weights.slice(0,5));qs.splice(qs.length-4,4,...qs.slice(0,4));
 const input=accessor(new Float32Array(ts),'SCALAR',5126,[0],[7.8]);
 return {name:state==='waiting'?'idle':state,samplers:[{input,output:accessor(new Float32Array(weights),'SCALAR',5126),interpolation:'LINEAR'},{input,output:accessor(new Float32Array(qs),'VEC4',5126),interpolation:'LINEAR'}],channels:[{sampler:0,target:{node:0,path:'weights'}},{sampler:1,target:{node:0,path:'rotation'}}]};
});
json.buffers[0].byteLength=offset;
const raw=Buffer.from(JSON.stringify(json)),j=Buffer.concat([raw,Buffer.alloc((4-raw.length%4)%4,32)]),bin=Buffer.concat(chunks);const header=Buffer.alloc(12);header.writeUInt32LE(0x46546c67);header.writeUInt32LE(2,4);header.writeUInt32LE(12+8+j.length+8+bin.length,8);const jh=Buffer.alloc(8);jh.writeUInt32LE(j.length);jh.writeUInt32LE(0x4e4f534a,4);const bh=Buffer.alloc(8);bh.writeUInt32LE(bin.length);bh.writeUInt32LE(0x004e4942,4);
await writeFile(new URL('../public/emma-relief.glb',import.meta.url),Buffer.concat([header,jh,j,bh,bin]));
console.log(`Exported ${g.attributes.position.count} vertices, ${g.index.count/3} triangles, ${header.readUInt32LE(8)} bytes.`);
