import fs from "node:fs/promises";
import { FileBlob, PresentationFile } from "@oai/artifact-tool";

const source = "/Users/shiying/Downloads/9106-pre.pptx";
const outDir = "/Users/shiying/Desktop/Slime/.codex_work/inspection";
await fs.mkdir(outDir, { recursive: true });

const presentation = await PresentationFile.importPptx(await FileBlob.load(source));
const snapshot = await presentation.inspect({
  kind: "deck,slide,textbox,shape,image,table,chart,notes,layout",
  include: "id,slide,name,title,text,textPreview,textChars,textLines,bbox,bboxUnit,isPlaceholder,placeholders,preview",
  maxChars: 100000,
});
await fs.writeFile(`${outDir}/snapshot.ndjson`, snapshot.ndjson);

const layoutSnapshot = await presentation.inspect({
  kind: "layout,slide",
  maxChars: 50000,
});
await fs.writeFile(`${outDir}/layouts.ndjson`, layoutSnapshot.ndjson);

for (const n of [2, 5, 6, 7, 8]) {
  const slide = presentation.slides.getItem(n - 1);
  const layout = await slide.export({ format: "layout" });
  await fs.writeFile(`${outDir}/slide-${n}.layout.json`, await layout.text());
  const preview = await slide.export({ format: "png", scale: 2 });
  await fs.writeFile(`${outDir}/slide-${n}.png`, new Uint8Array(await preview.arrayBuffer()));
}

console.log(JSON.stringify({ slideCount: presentation.slides.items.length, outDir }, null, 2));
