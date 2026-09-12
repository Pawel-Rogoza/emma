import * as THREE from 'three';

// Volumetric, hand-authored anatomical blockout. No photo reconstruction or fur groom.
export function createHead(){
 const root=new THREE.Group();root.name='Emma_Volumetric_Blockout';
 const head=new THREE.Group();head.name='HeadPivot';root.add(head);
 const mat=(color,roughness=.85)=>new THREE.MeshStandardMaterial({color,roughness});
 const coat=mat('#242127'),tan=mat('#aa764c'),cream=mat('#d7c3a4'),nose=mat('#161318',.3),eye=mat('#120d0b',.12),inner=mat('#795447');
 function ellipsoid(parent,name,position,scale,material){const mesh=new THREE.Mesh(new THREE.SphereGeometry(1,32,24),material);mesh.name=name;mesh.position.set(...position);mesh.scale.set(...scale);parent.add(mesh);return mesh;}
 ellipsoid(head,'Cranium',[0,0,0],[.56,.59,.43],coat);
 ellipsoid(head,'Neck',[0,-.51,-.14],[.36,.42,.32],coat);
 ellipsoid(head,'MuzzleBridge',[0,-.13,.4],[.23,.23,.34],coat);
 const jaw=new THREE.Group();jaw.name='JawPivot';jaw.position.set(0,-.29,.18);head.add(jaw);
 ellipsoid(jaw,'Mandible',[0,-.07,.29],[.22,.105,.28],cream);
 ellipsoid(jaw,'MouthInterior',[0,.015,.29],[.175,.025,.23],nose);
 ellipsoid(jaw,'Tongue',[0,.033,.4],[.1,.015,.10],mat('#9c656c'));
 for(const side of [-1,1]){
  ellipsoid(head,`Cheek_${side}`,[side*.31,-.24,.29],[.22,.22,.22],tan);
  ellipsoid(head,`MuzzlePad_${side}`,[side*.105,-.205,.60],[.145,.13,.16],cream);
 }
 ellipsoid(head,'Nose',[0,-.10,.767],[.137,.098,.086],nose);
 for(const side of [-1,1])ellipsoid(head,`Nostril_${side}`,[side*.067,-.1,.842],[.032,.022,.01],mat('#050405'));
 const lids=[],ears=[];
 for(const side of [-1,1]){
  const center=[side*.285,.13,.36];
  ellipsoid(head,`EyeSocket_${side}`,center,[.183,.198,.10],coat);
  ellipsoid(head,`Eyeball_${side}`,[side*.285,.13,.407],[.135,.15,.11],eye);
  ellipsoid(head,`BrowMark_${side}`,[side*.285,.36,.35],[.102,.061,.037],cream);
  // Upper hemispherical shell rotates around the eyeball, covering it physically.
  const pivot=new THREE.Group();pivot.name=`UpperLidPivot_${side}`;pivot.position.set(side*.285,.13,.407);head.add(pivot);
  const lid=new THREE.Mesh(new THREE.SphereGeometry(1,32,16,0,Math.PI*2,0,Math.PI/2),coat);
  lid.name=`UpperLid_${side}`;lid.scale.set(.143,.158,.12);pivot.add(lid);pivot.rotation.x=-1.36;lids.push(pivot);
  const ear=new THREE.Group();ear.name=`EarPivot_${side}`;ear.position.set(side*.40,.38,-.02);head.add(ear);ears.push(ear);
  // Closed tapered ear surface, front bowl plus convex back.
  const vertices=[],indices=[],rings=14,segments=24;
  for(let r=0;r<=rings;r++){
   const t=r/rings,width=.24*(1-t)*(.8+.5*Math.sin(t*Math.PI));
   for(let s=0;s<segments;s++){const a=s/segments*Math.PI*2;vertices.push(side*(.24*t)+Math.cos(a)*Math.max(.001,width),t*.84,Math.sin(a)*(.062*(1-t)+.002));}
  }
  for(let r=0;r<rings;r++)for(let s=0;s<segments;s++){const a=r*segments+s,b=r*segments+(s+1)%segments,c=a+segments,d=b+segments;indices.push(a,c,b,b,c,d);}
  for(const r of [0,rings])for(let s=1;s<segments-1;s++){const b=r*segments;indices.push(b,b+(r===0?s:s+1),b+(r===0?s+1:s));}
  const geo=new THREE.BufferGeometry();geo.setAttribute('position',new THREE.Float32BufferAttribute(vertices,3));geo.setIndex(indices);geo.computeVertexNormals();
  const shell=new THREE.Mesh(geo,coat);shell.name=`EarShell_${side}`;ear.add(shell);
  const inset=ellipsoid(ear,`EarInner_${side}`,[side*.09,.30,.044],[.125,.29,.022],inner);inset.rotation.z=-side*.24;
 }
 return {root,head,jaw,lids,ears};
}

export function animateHead(model,pose){
 model.head.rotation.set(pose.x,pose.y,pose.z);
 model.jaw.rotation.x=pose.morphs[4]*.24;
 model.lids.forEach((lid,i)=>lid.rotation.x=-1.36+pose.morphs[i]*2.75);
 model.ears.forEach((ear,i)=>{ear.rotation.z=(i===0?1:-1)*pose.morphs[i+2]*.16;ear.rotation.x=pose.morphs[i+2]*.09;});
}
