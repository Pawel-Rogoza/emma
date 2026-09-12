import * as THREE from 'three';
import {createHead} from './head-model.js';

// Deterministic geometry-only groom: exportable strands, no screen-space fake fur.
export function createGroomedHead(){
 const model=createHead();model.root.name='Emma_Groom_Study';
 let seed=719;const random=()=>((seed=Math.imul(seed,1664525)+1013904223>>>0)/4294967296);
 const furMaterial=new THREE.MeshStandardMaterial({vertexColors:true,roughness:.78,side:THREE.DoubleSide});
 const dark=new THREE.Color('#241e1c'),warm=new THREE.Color('#a87649'),pale=new THREE.Color('#d5b48b');
 function groom(mesh,count,length,color,filter=()=>true){
  const positions=[],colors=[],indices=[];
  mesh.updateMatrix();
  for(let n=0;n<count;n++){
   const y=random()*2-1,a=random()*Math.PI*2,r=Math.sqrt(1-y*y),unit=new THREE.Vector3(r*Math.cos(a),y,r*Math.sin(a));
   if(!filter(unit))continue;
   const root=unit.clone().multiply(mesh.scale).applyQuaternion(mesh.quaternion).add(mesh.position);
   const normal=unit.clone().divide(mesh.scale).normalize().applyQuaternion(mesh.quaternion);
   const len=length*(.5+random());
   const flow=new THREE.Vector3(root.x*.35,-.85,.10).normalize();
   const width=.0012+random()*.0012;
   const tangent=new THREE.Vector3().crossVectors(normal,flow).normalize();
   if(tangent.lengthSq()<.01)tangent.set(1,0,0);
   const c=color.clone().multiplyScalar(.55+random()*.95),base=positions.length/3;
   for(let k=0;k<=4;k++){
    const t=k/4,point=root.clone().addScaledVector(normal,len*(t-.65*t*t)).addScaledVector(flow,len*t*t);
    point.addScaledVector(tangent,Math.sin(t*5+n)*len*.08*t);
    for(const side of [-1,1]){const v=point.clone().addScaledVector(tangent,side*width*(1-t*.97));positions.push(...v);colors.push(c.r,c.g,c.b);}
    if(k<4){const b=base+k*2;indices.push(b,b+1,b+2,b+1,b+3,b+2);}
   }
  }
  const geometry=new THREE.BufferGeometry();geometry.setAttribute('position',new THREE.Float32BufferAttribute(positions,3));geometry.setAttribute('color',new THREE.Float32BufferAttribute(colors,3));geometry.setIndex(indices);geometry.computeVertexNormals();
  const fur=new THREE.Mesh(geometry,furMaterial);fur.name=`Groom_${mesh.name}`;mesh.parent.add(fur);
 }
 const meshes=[];model.root.traverse(n=>{if(n.isMesh)meshes.push(n);});
 for(const mesh of meshes){
  const name=mesh.name;
  if(name==='Cranium')groom(mesh,13000,.08,dark,u=>!(u.z>.6&&u.y>-.2&&u.y<.5&&Math.abs(u.x)>.3&&Math.abs(u.x)<.8));
  if(name==='Neck')groom(mesh,7500,.27,dark);
  if(name.startsWith('Cheek')){mesh.scale.set(.20,.19,.18);groom(mesh,3200,.14,warm);}
  if(name.startsWith('MuzzlePad')){mesh.scale.set(.14,.11,.14);groom(mesh,2000,.036,pale);}
  if(name==='MuzzleBridge')groom(mesh,1800,.026,dark);
  if(name==='Mandible')groom(mesh,2000,.08,pale,u=>u.y<.2);
  if(name.startsWith('BrowMark')){mesh.scale.set(.095,.047,.025);groom(mesh,700,.035,pale);}
  if(name.startsWith('EarInner'))groom(mesh,1500,.09,pale,u=>u.z>0);
  if(name.startsWith('Eyeball')){
   mesh.position.z=.365;mesh.scale.set(.12,.132,.075);
   mesh.material=new THREE.MeshPhysicalMaterial({color:'#20110a',roughness:.08,clearcoat:1,clearcoatRoughness:.03});
   const pupil=new THREE.Mesh(new THREE.SphereGeometry(1,24,16),new THREE.MeshPhysicalMaterial({color:'#050404',roughness:.06,clearcoat:1}));
   pupil.name=`Pupil_${name}`;pupil.position.copy(mesh.position).add(new THREE.Vector3(0,0,.069));pupil.scale.set(.072,.080,.009);mesh.parent.add(pupil);
  }
 }
 // Keep lid shells concentric with the revised eye surfaces.
 for(const pivot of model.lids){pivot.position.z=.365;pivot.children[0].scale.set(.128,.14,.084);}
 // Long fringes are attached to ear pivots so they follow the existing animation.
 for(let i=0;i<2;i++){
  const side=i===0?-1:1,ear=model.ears[i];
  const emitter=new THREE.Mesh(new THREE.SphereGeometry(1,8,8));emitter.name=`EarFringe_${side}`;
  emitter.position.set(side*.08,.29,-.015);emitter.scale.set(.22,.38,.08);ear.add(emitter);
  groom(emitter,6500,.32,dark,u=>Math.abs(u.x)>.4||u.z<0);ear.remove(emitter);emitter.geometry.dispose();emitter.material.dispose();
 }
 model.root.userData={stage:'Groom and material study; not final photoreal likeness',groom:'Explicit tapered ribbons, attached to animated rigid parts',mobileReady:false};
 return model;
}
