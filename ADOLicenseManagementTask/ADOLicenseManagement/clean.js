import { deleteAsync } from "del";

async function clean() {
    await deleteAsync([
        "./dist/src",
        "./dist/test",
        "./task/*.js",
        "./task/*.js.map",
        "./task/node_modules"
    ]);
    console.log("Clean complete.");
}

clean();
