const {surgeExpandFolders}=require('../userscript/folder-core.js');
const assert=require('node:assert/strict');
(async()=>{
 const calls=[];
 const f=(fid,name)=>({fid,file_name:name,file:true});
 const d=(fid,name)=>({fid,file_name:name,file:false});
 const results=await surgeExpandFolders([{...d('a','剧集'),stoken:'fixture'}],async(item,page,token)=>{
 calls.push([item.fid,page]); assert.equal(token,'fixture');
 return ({a:{1:[f('1','01.mp4'),d('b','子目录')],2:[f('2','02.mp4')]},b:{1:[f('3','01.mp4')]}})[item.fid]?.[page]||[];
 });
 assert.deepEqual(results.map(x=>x.surgePath),['剧集/01.mp4','剧集/子目录/01.mp4','剧集/02.mp4']);
 assert(calls.some(x=>x[0]==='a'&&x[1]===3));
 await assert.rejects(surgeExpandFolders([d('a','..')],async()=>[]));
 await assert.rejects(surgeExpandFolders([d('a','a')],async()=>[f('1','one')]),/分页重复/);
 assert.deepEqual(await surgeExpandFolders([d('a','empty')],async()=>[]),[]);
 await assert.rejects(surgeExpandFolders([d('a','a')],async()=>{throw Error('expired')}),/expired/);
 console.log('PASS: recursion, pagination, inherited token, duplicate pages, empty folder, API errors, invalid names');
})();
