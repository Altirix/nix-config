// Thumb entries for an ARM image Ghidra imports headless (servers/rea.nix, /etc/rea/ghidra-scripts): REA's own raw
// loader and seeds decode everything as ARM, so Thumb functions come out as garbage. Run before analysis:
//   -preScript ReaThumbSeeds.java <seeds>     one `address [name]` per line, low bit set or not, # comments
//   -preScript ReaThumbSeeds.java --all       the whole image is Thumb (Cortex-M style, Thumb-only firmware)
// Each seed gets TMode=1, is disassembled and made a function; analysis then follows its calls.
//@category REA
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.Register;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.ProgramContext;
import ghidra.program.model.mem.MemoryBlock;
import java.math.BigInteger;
import java.nio.file.Files;
import java.nio.file.Path;

public class ReaThumbSeeds extends GhidraScript {
    @Override
    public void run() throws Exception {
        ProgramContext context = currentProgram.getProgramContext();
        Register tmode = context.getRegister("TMode");
        if (tmode == null) {
            printerr("REA thumb seeds: no TMode register, import with an ARM language (-processor ARM:LE:32:v7)");
            return;
        }
        boolean all = false;
        String seeds = null;
        for (String arg : getScriptArgs()) {
            if (arg.equals("--all")) all = true;
            else seeds = arg;
        }
        if (all) {
            for (MemoryBlock block : currentProgram.getMemory().getBlocks()) {
                if (block.isInitialized()) context.setValue(tmode, block.getStart(), block.getEnd(), BigInteger.ONE);
            }
        }
        int created = 0, existing = 0, failed = 0;
        if (seeds != null) {
            for (String raw : Files.readAllLines(Path.of(seeds))) {
                String line = raw.strip();
                if (line.isEmpty() || line.startsWith("#")) continue;
                String[] fields = line.split("\\s+");
                Address address = toAddr(Long.decode(fields[0]) & ~1L);
                context.setValue(tmode, address, address, BigInteger.ONE);
                if (getFunctionAt(address) != null) {
                    existing++;
                    continue;
                }
                disassemble(address);
                Function function = getInstructionAt(address) == null
                    ? null
                    : createFunction(address, fields.length > 1 ? fields[1] : null);
                if (function != null) created++;
                else {
                    failed++;
                    if (failed <= 20) println("REA thumb seed failed: " + address);
                }
            }
        }
        println("REA thumb seeds: created " + created + ", existing " + existing + ", failed " + failed
            + (all ? ", whole image Thumb" : ""));
    }
}
