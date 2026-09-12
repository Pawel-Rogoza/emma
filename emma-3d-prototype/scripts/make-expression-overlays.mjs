import {readFile,writeFile} from 'node:fs/promises';
import {PNG} from 'pngjs';

const root=new URL('../public/',import.meta.url);
const base=PNG.sync.read(await readFile(new URL('emma-avatar-refined.png',root)));
const specs=[
 ['emma-blink.png','emma-blink-overlay.png',[[.383,.408,.102,.088],[.594,.423,.102,.088]]],
 ['emma-speak.png','emma-speak-overlay.png',[[.5,.635,.18,.105]]]
];
for(const [input,output,ellipses] of specs){
 const source=PNG.sync.read(await readFile(new URL(input,root)));
 if(source.width!==base.width||source.height!==base.height)throw new Error(`${input}: dimensions do not match`);
 const result=new PNG({width:base.width,height:base.height});
 for(let y=0;y<base.height;y++)for(let x=0;x<base.width;x++){
  const i=(y*base.width+x)*4;
  let mask=0;
  for(const [cx,cy,rx,ry] of ellipses){
   const d=Math.hypot((x/base.width-cx)/rx,(y/base.height-cy)/ry);
   const soft=Math.max(0,Math.min(1,(1-d)/.28));mask=Math.max(mask,soft*soft*(3-2*soft));
  }
  result.data[i]=source.data[i];result.data[i+1]=source.data[i+1];result.data[i+2]=source.data[i+2];
  result.data[i+3]=Math.round(base.data[i+3]*mask);
 }
 await writeFile(new URL(output,root),PNG.sync.write(result));
 console.log(`${output}: localized alpha restored from approved portrait`);
}
