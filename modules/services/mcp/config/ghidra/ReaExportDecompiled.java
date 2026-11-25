// Every function's decompiled C into one file, after analysis (servers/rea.nix, /etc/rea/ghidra-scripts):
//   -postScript ReaExportDecompiled.java <output.c>
// Each function is headed `// <name> @ <entry>`; one the decompiler gives up on says why instead.
//@category REA
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;

public class ReaExportDecompiled extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 1) {
            printerr("REA export: give the output file, -postScript ReaExportDecompiled.java <output.c>");
            return;
        }
        DecompInterface decompiler = new DecompInterface();
        decompiler.openProgram(currentProgram);
        int done = 0, failed = 0;
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            for (Function function : currentProgram.getFunctionManager().getFunctions(true)) {
                monitor.checkCancelled();
                DecompileResults result = decompiler.decompileFunction(function, 60, monitor);
                out.println("// " + function.getName() + " @ " + function.getEntryPoint());
                if (result.decompileCompleted()) {
                    out.println(result.getDecompiledFunction().getC());
                    done++;
                } else {
                    out.println("// decompile failed: " + result.getErrorMessage());
                    failed++;
                }
            }
        } finally {
            decompiler.dispose();
        }
        println("REA export: " + done + " functions to " + args[0] + ", " + failed + " failed");
    }
}
