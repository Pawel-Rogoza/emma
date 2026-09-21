import * as THREE from 'three';
import {OrbitControls} from 'three/addons/controls/OrbitControls.js';
import {createHead,animateHead} from './head-model.js';
import {poseAt} from './animation.js';
import {createGroomedHead} from './head-groom.js';
const canvas=document.querySelector('canvas'),renderer=new THREE.WebGLRenderer({canvas,antialias:true});
renderer.setPixelRatio(Math.min(devicePixelRatio,2));renderer.setClearColor('#e9e8e5');
const scene=new THREE.Scene(),camera=new THREE.PerspectiveCamera(36,1,.1,30);camera.position.set(0,.35,4.8);
const controls=new OrbitControls(camera,canvas);controls.target.set(0,.18,0);controls.enableDamping=true;controls.minDistance=2.5;controls.maxDistance=7;controls.enablePan=false;
scene.add(new THREE.HemisphereLight('#f9f5ee','#827e89',2));
for(const [x,y,z,intensity] of [[-3,4,5,3],[3,2,-3,4]]){const light=new THREE.DirectionalLight('#fff5e9',intensity);light.position.set(x,y,z);scene.add(light);}
const model=new URLSearchParams(location.search).has('groom')?createGroomedHead():createHead();scene.add(model.root);
if(new URLSearchParams(location.search).has('groom')){document.querySelector('h1').textContent='Emma / studium sierści i materiałów';document.querySelector('header p').textContent='Przestrzenna sierść, oczy i materiały na animowanej bryle. Wersja robocza — podobieństwo i fotorealizm wymagają dalszego dopracowania.';}
const reduced=matchMedia('(prefers-reduced-motion: reduce)');let rotating=!reduced.matches,speaking=false,last=0,time=0;
const rotate=document.querySelector('#rotate');function label(){rotate.textContent=rotating?'Zatrzymaj obrót':'Obróć model';}label();
rotate.onclick=()=>{rotating=!rotating;label();};
document.querySelector('#motion').onclick=e=>{speaking=!speaking;e.target.textContent=speaking?'Zatrzymaj ruch pyska':'Pokaż ruch pyska';};
function resize(){renderer.setSize(innerWidth,innerHeight,false);camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();}addEventListener('resize',resize);resize();
renderer.setAnimationLoop(now=>{if(document.hidden||now-last<1000/30)return;const dt=Math.min((now-last)/1000,.05);last=now;if(!reduced.matches)time+=dt;
 if(rotating&&!reduced.matches)model.root.rotation.y+=dt*.24;
 animateHead(model,poseAt(time,speaking?'speaking':'waiting',speaking?.55+.3*Math.sin(time*7):0));controls.update();renderer.render(scene,camera);
});
