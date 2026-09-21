import {writeFile} from 'node:fs/promises';
import * as THREE from 'three';
import {GLTFExporter} from 'three/addons/exporters/GLTFExporter.js';
import validator from 'gltf-validator';
import {createHead,animateHead} from '../src/head-model.js';
import {poseAt} from '../src/animation.js';
import {createGroomedHead} from '../src/head-groom.js';

// GLTFExporter uses FileReader for buffer packing. No image or DOM dependency here.
globalThis.FileReader=class{
 readAsArrayBuffer(blob){blob.arrayBuffer().then(result=>{this.result=result;this.onloadend?.();});}
};
const groom=process.argv.includes('--groom');
const model=groom?createGroomedHead():createHead();
const animated=[model.head,model.jaw,...model.lids,...model.ears];
const clips=['waiting','listening','thinking','speaking','interrupted'].map(state=>{
 const times=[],values=animated.map(()=>[]);
 for(let frame=0;frame<=234;frame++){
  const t=frame/30,p=poseAt(t,state,state==='speaking'?.6:0),initial=poseAt(0,state,state==='speaking'?.6:0);
  const u=Math.max(0,(t-7.2)/.6),blend=u*u*(3-2*u);
  for(const k of ['x','y','z'])p[k]+=(initial[k]-p[k])*blend;
  p.morphs=p.morphs.map((v,i)=>v+(initial.morphs[i]-v)*blend);
  animateHead(model,p);times.push(t);animated.forEach((node,i)=>values[i].push(...node.quaternion.toArray()));
 }
 return new THREE.AnimationClip(state==='waiting'?'idle':state,7.8,animated.map((node,i)=>new THREE.QuaternionKeyframeTrack(`${node.name}.quaternion`,times,values[i])));
});
animateHead(model,poseAt(0));
model.root.userData={...model.root.userData,stage:groom?'Groom study, not final likeness or photoreal asset':'Volumetric blockout, not final likeness or photoreal asset',units:'prototype units',source:'Hand-authored geometry; no reconstructed scan'};
const result=await new GLTFExporter().parseAsync(model.root,{binary:true,animations:clips});
const report=await validator.validateBytes(new Uint8Array(result));
console.log(JSON.stringify(report.issues,null,2));
if(report.issues.numErrors)throw new Error('GLB validation failed');
await writeFile(new URL(groom?'../public/emma-head-groom.glb':'../public/emma-head-blockout.glb',import.meta.url),Buffer.from(result));
console.log(`Exported volumetric head: ${result.byteLength} bytes, ${clips.length} clips.`);
