// Deterministic motion in seconds, independent of frame rate. No audio ownership.
export function poseAt(t,state='waiting',level=0){
 const pulse=(phase,start,duration)=>{const a=(phase-start)/duration;return a>=0&&a<1?Math.sin(a*Math.PI)**2:0;};
 const cycle=t%7.8;
 const blink=Math.max(pulse(cycle,2.6,.21),pulse(cycle,6.1,.19),pulse(cycle,6.44,.17));
 const twitch=pulse(t%11.2,4.5,.48);
 const speaking=state==='speaking';
 const jaw=speaking?Math.max(0,Math.min(1,level))*(.72+.28*Math.sin(t*17)):0;
 const listening=state==='listening',thinking=state==='thinking';
 const lookCycle=t%9.4,lookPulse=pulse(lookCycle,3.15,.8),returnPulse=pulse(lookCycle,4.05,.65);
 const gazeX=(lookPulse-returnPulse)*.0045+(listening?Math.sin(t*.7)*.0015:0);
 const gazeY=(thinking?-.0018:0)+Math.sin(t*.31)*.0007;
 return {morphs:[blink,blink*.98,(listening?.48:.1)+twitch*.55,(listening?.35:.08)+pulse((t+1.7)%13,5,.5)*.5,jaw],
  x:Math.sin(t*.73)*.012+(listening?-.03:0)+jaw*.007,
  y:Math.sin(t*.43)*.026+(thinking?.035:0),
  z:Math.sin(t*.58)*.014+(listening?-.06:thinking?.028:0),
  breath:1+Math.sin(t*1.5)*.003,gazeX,gazeY};
}
