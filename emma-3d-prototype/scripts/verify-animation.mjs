import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import validator from 'gltf-validator';
import {poseAt} from '../src/animation.js';
import {makeGeometry,morphNames} from '../src/relief.js';

for(const state of ['waiting','listening','thinking','speaking','interrupted']){
 for(let frame=0;frame<1800;frame++){
  const p=poseAt(frame/30,state,.8);
  assert.ok([p.x,p.y,p.z,p.breath,p.gazeX,p.gazeY,...p.morphs].every(Number.isFinite));
  assert.ok(p.morphs.every(v=>v>=0&&v<=1.05));
  if(state!=='speaking')assert.equal(p.morphs[4],0);
 }
}
assert.ok(poseAt(2.705).morphs[0]>.99);
assert.equal(poseAt(2.4).morphs[0],0);
const geometry=makeGeometry();
assert.equal(geometry.morphAttributes.position.length,morphNames.length);
for(const target of geometry.morphAttributes.position){
 assert.equal(target.count,geometry.attributes.position.count);
 assert.ok(target.array.every(Number.isFinite));
}
const bytes=await readFile(new URL('../public/emma-relief.glb',import.meta.url));
const report=await validator.validateBytes(new Uint8Array(bytes));
console.log(JSON.stringify(report.issues,null,2));
assert.equal(report.issues.numErrors,0,'GLB must have no validation errors');
console.log('Animation: 9,000 sampled poses and five morph targets OK. GLB validation passed.');
