import createNgspiceModule from "https://cdn.jsdelivr.net/npm/@o.z/ngspice-wasm@0.0.0/ngspice.js";

let ngspice;
let outputs = [];

window.NGSpiceBridge = {
    init: async function() {
        console.log("Initializing NGSpice WASM...");
        ngspice = await createNgspiceModule({
            locateFile: (file) => `https://cdn.jsdelivr.net/npm/@o.z/ngspice-wasm@0.0.0/${file}`,
            print: (text) => {
                outputs.push(text);
                // console.log("NGSpice stdout:", text);
            },
            printErr: (text) => {
                console.error("NGSpice stderr:", text);
            }
        });
        console.log("NGSpice initialized.");
    },

    loadNetlist: function(netlistContent) {
        if (!ngspice) throw new Error("NGSpice not initialized");
        ngspice.FS.writeFile("/circuit.cir", netlistContent);
        
        // Load the netlist
        ngspice._ngSpice_Command("source /circuit.cir");
    },

    sendCommand: function(command) {
        if (!ngspice) throw new Error("NGSpice not initialized");
        outputs = []; // Clear outputs before command
        
        // Convert JS string to C string pointer
        // Ensure the string is null-terminated and allocate enough memory
        const lengthBytes = ngspice.lengthBytesUTF8(command) + 1;
        const cmdPtr = ngspice._malloc(lengthBytes);
        ngspice.stringToUTF8(command, cmdPtr, lengthBytes);
        
        // Execute
        ngspice._ngSpice_Command(cmdPtr);
        
        // Free
        ngspice._free(cmdPtr);
        
        return outputs.join("\n");
    },

    getVectorValue: function(vectorName) {
        const out = this.sendCommand(`print ${vectorName}`);
        // Parse "V(1) = 5.0000e+00"
        const lines = out.split('\n');
        for (let i = lines.length - 1; i >= 0; i--) {
            const line = lines[i].trim();
            // Typical output: "vectorName = value"
            // Wait, ngspice print output might look like:
            // "v1 = 5.000000e+00"
            // "i(v1) = 1.00000e-03"
            const parts = line.split('=');
            if (parts.length === 2) {
                return parseFloat(parts[1].trim());
            }
        }
        return 0.0;
    }
};
