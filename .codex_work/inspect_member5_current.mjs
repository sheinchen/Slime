import { FileBlob, PresentationFile } from "@oai/artifact-tool";

const source = "/Users/shiying/Desktop/Slime/output/9106-pre_member5_completed.pptx";
const presentation = await PresentationFile.importPptx(await FileBlob.load(source));
const snapshot = await presentation.inspect({
  kind: "slide,textbox,shape,notes",
  target: { id: "sl/fu1gfa1s", beforeLines: 0, afterLines: 40 },
  include: "id,slide,name,title,text,textPreview,bbox,bboxUnit",
  maxChars: 30000,
});
console.log(snapshot.ndjson);
