package ai.auralis.semiconductor.eda;

import java.util.Map;
import java.util.regex.Pattern;

import org.springframework.ai.mcp.annotation.McpTool;
import org.springframework.ai.mcp.annotation.McpToolParam;
import org.springframework.stereotype.Component;

/** The individual EDA tools, over MCP. */
@Component
public class EdaTools {

    private static final Pattern IDENT = Pattern.compile("^[A-Za-z_][A-Za-z0-9_$]*$");

    private final EdaRunner eda;

    public EdaTools(EdaRunner eda) {
        this.eda = eda;
    }

    @McpTool(name = "rtl_lint", description = """
            Lint and elaborate SystemVerilog/Verilog RTL with Verilator (--lint-only -Wall).
            Pass all modules of the design as one source. Returns warnings/errors, or
            'LINT CLEAN'. Run it after every RTL change, before simulating.""")
    public String lint(@McpToolParam(description = "All RTL modules as one SystemVerilog source") String rtl,
                       @McpToolParam(description = "Top module name") String top) {
        if (!IDENT.matcher(top).matches()) {
            return "invalid top module name";
        }
        return format(eda.run(Map.of("design.sv", rtl), lintScript("design.sv", top)));
    }

    @McpTool(name = "rtl_simulate", description = """
            Simulate RTL with a self-checking testbench using Icarus Verilog (-g2012). The
            testbench should $display PASS/FAIL lines and call $finish. Returns compile errors
            or the simulation output.""")
    public String simulate(@McpToolParam(description = "All RTL modules as one SystemVerilog source") String rtl,
                           @McpToolParam(description = "Testbench source") String testbench,
                           @McpToolParam(description = "Testbench top module name") String tbTop) {
        if (!IDENT.matcher(tbTop).matches()) {
            return "invalid testbench module name";
        }
        return format(eda.run(Map.of("design.sv", rtl, "tb.sv", testbench),
                simScript("design.sv tb.sv", tbTop)));
    }

    @McpTool(name = "rtl_synthesize", description = """
            Synthesize RTL with Yosys (generic synth) and report cell count, cell types and
            wiring — a technology-independent area proxy — plus latches and multi-driver
            problems found by 'check'.""")
    public String synthesize(@McpToolParam(description = "All RTL modules as one SystemVerilog source") String rtl,
                             @McpToolParam(description = "Top module name") String top) {
        if (!IDENT.matcher(top).matches()) {
            return "invalid top module name";
        }
        return format(eda.run(Map.of("design.sv", rtl), synthScript("design.sv", top)));
    }

    static String lintScript(String files, String top) {
        return "verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM"
                + " --top-module " + top + " " + files + " && echo 'LINT CLEAN'";
    }

    static String simScript(String files, String tbTop) {
        return "iverilog -g2012 -s " + tbTop + " -o sim " + files + " && timeout 60 vvp -n sim";
    }

    static String synthScript(String files, String top) {
        return "yosys -q -p 'read_verilog -sv " + files + "; synth -top " + top
                + "; check; tee -o stat.txt stat' >/dev/null 2>yosys.err; s=$?;"
                + " cat yosys.err; cat stat.txt 2>/dev/null; exit $s";
    }

    static String format(EdaRunner.Result r) {
        return (r.ok() ? "" : "FAILED (exit " + r.exitCode() + ")\n") + r.output();
    }
}
