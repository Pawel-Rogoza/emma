import * as THREE from 'three';
// Hand-authored shallow depth approximation. Not a reconstructed animal volume.
export function depth(x,y){
 const g=(cx,cy,sx,sy)=>Math.exp(-(((x-cx)/sx)**2)-(((y-cy)/sy)**2));
 return .24*g(0,-.1,.60,.60)+.18*g(-.06,-.08,.19,.19)+.07*g(-.42,.55,.22,.45)+.07*g(.42,.50,.23,.44)+.09*g(0,-.64,.65,.50);
}
export const morphNames=['blinkLeft','blinkRight','earLeft','earRight','jawOpen'];
export function morphDelta(name,x,y){
 const gaussian=(cx,cy,sx,sy)=>Math.exp(-(((x-cx)/sx)**2)-(((y-cy)/sy)**2));
 if(name.startsWith('blink')){
  const left=name==='blinkLeft',cx=left?-.25:.18,cy=left?.18:.12;
  const w=gaussian(cx,cy,.063,.082);
  return [0,-(y-cy)*.96*w,-.006*w];
 }
 if(name.startsWith('ear')){
  const side=name==='earLeft'?-1:1;
  const w=gaussian(side*.46,.66,.27,.36)*Math.min(1,Math.max(0,(y-.28)/.2));
  return [side*(y-.3)*.09*w,-Math.abs(x-side*.28)*.065*w,.035*w];
 }
 const w=gaussian(-.08,-.27,.20,.13);
 return [0,-.035*w,.012*w];
}
export function makeGeometry(){
 const g=new THREE.PlaneGeometry(2,2,160,160),p=g.attributes.position;
 for(let i=0;i<p.count;i++)p.setZ(i,depth(p.getX(i),p.getY(i)));
 g.morphTargetsRelative=true;
 g.morphAttributes.position=morphNames.map(name=>{const a=new Float32Array(p.count*3);for(let i=0;i<p.count;i++)a.set(morphDelta(name,p.getX(i),p.getY(i)),i*3);const attribute=new THREE.Float32BufferAttribute(a,3);attribute.name=name;return attribute;});
 g.computeVertexNormals();return g;
}
