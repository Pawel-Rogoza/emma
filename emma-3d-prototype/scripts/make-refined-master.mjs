import {readFile,writeFile} from 'node:fs/promises';
import {PNG} from 'pngjs';

const input=new URL('../public/emma-avatar.png',import.meta.url);
const output=new URL('../public/emma-avatar-refined.png',import.meta.url);
const image=PNG.sync.read(await readFile(input));
for(let y=0;y<image.height;y++)for(let x=0;x<image.width;x++){
 const ny=y/(image.height-1),nx=x/(image.width-1),i=(y*image.width+x)*4;
 // The real Emma has a slender neck/chest. Keep the entire face and cheek line,
 // then taper only the lower coat with a broad feather that preserves stray hairs.
 const progress=Math.max(0,Math.min(1,(ny-.60)/.36));
 const smooth=progress*progress*(3-2*progress);
 const halfWidth=.49-(.15*smooth);
 const edge=(Math.abs(nx-.5)-halfWidth)/.032;
 const clip=1-Math.max(0,Math.min(1,edge));
 image.data[i+3]=Math.round(image.data[i+3]*clip);
}
await writeFile(output,PNG.sync.write(image));
console.log('emma-avatar-refined.png: face preserved, lower alpha silhouette tapered');
