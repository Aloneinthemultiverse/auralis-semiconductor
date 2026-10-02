package ai.auralis.semiconductor.domain;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.springframework.ai.mcp.annotation.McpTool;
import org.springframework.ai.mcp.annotation.McpToolParam;
import org.springframework.stereotype.Component;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.json.JsonMapper;

import ai.auralis.semiconductor.eda.EdaRunner;

/**
 * The semiconductor design domain, as Auralis discovers it: a
 * {@code semiconductor_guidance} + {@code semiconductor_validate} tool pair.
 * Validation lints the RTL, runs every testbench, and synthesizes the top.
 */
@Component
public class SemiconductorDomain {

    private static final Pattern MODULE_DECL = Pattern.compile("\\bmodule\\s+([A-Za-z_][A-Za-z0-9_$]*)");
    private static final Pattern CELLS = Pattern.compile("Number of cells:\\s+(\\d+)");
    private static final Pattern COMMENTS = Pattern.compile("(?s)//[^\\n]*|/\\*.*?\\*/");

    private final EdaRunner eda;
    private final JsonMapper json;

    public SemiconductorDomain(EdaRunner eda, JsonMapper json) {
        this.eda = eda;
        this.json = json;
    }

    @McpTool(name = "semiconductor_guidance", description = """
            Semiconductor / digital hardware design: chips, processors, accelerators, RTL,
            SystemVerilog/Verilog, ASIC and FPGA logic, buses and interfaces, memory
            controllers, pipelines, PPA (power, performance, area). Returns the design
            guidance Auralis follows in this domain.""")
    public String guidance() {
        return """
                Produce synthesizable SystemVerilog (IEEE 1800-2017 subset that Verilator,
                Icarus Verilog and Yosys accept):
                - One module per file, file named after the module (e.g. `// file: alu.sv`).
                  Use `always_ff`/`always_comb`, explicit widths, synchronous active-low reset
                  `rst_n` unless the requirements say otherwise; no latches, no initial blocks
                  in RTL, no vendor primitives.
                - Make the top module's ports match the specified interface exactly; state the
                  top module name in the description.
                - Provide at least one self-checking testbench `tb_<top>.sv` (module `tb_<top>`)
                  that drives directed and edge-case stimulus, compares against a reference
                  model, `$display`s `PASS <check>` / `FAIL <check>` for each check, prints
                  `ALL TESTS PASSED` only if nothing failed, and calls `$finish`.
                - In the description give the microarchitecture (block diagram in words,
                  pipeline stages, FSM states, widths), how each requirement is met, and the
                  expected PPA trade-offs.
                Validation will lint (Verilator -Wall), simulate every tb_*.sv (Icarus) and
                synthesize the top (Yosys) — design so all three pass.""";
    }

    @McpTool(name = "semiconductor_validate", description = """
            Validate a semiconductor design's files: Verilator lint of all RTL, Icarus
            simulation of every tb_*.sv testbench, Yosys synthesis of the top module (cell
            count as an area proxy). Returns a report ending in a SUMMARY line.""")
    public String validate(
            @McpToolParam(description = "JSON object mapping file name to file content")
            String filesJson) {
        Map<String, String> files;
        try {
            files = json.readValue(filesJson, new TypeReference<LinkedHashMap<String, String>>() { });
        } catch (Exception ex) {
            return "SUMMARY: invalid input — filesJson must be a JSON object of name -> content";
        }
        return validate(files);
    }

    String validate(Map<String, String> files) {
        Map<String, String> rtl = new LinkedHashMap<>();
        Map<String, String> tbs = new LinkedHashMap<>();
        files.forEach((name, content) -> {
            String lower = name.toLowerCase(Locale.ROOT);
            if (!(lower.endsWith(".sv") || lower.endsWith(".v"))) {
                return;
            }
            String base = lower.substring(lower.lastIndexOf('/') + 1);
            (base.startsWith("tb") || base.contains("_tb") ? tbs : rtl).put(name, content);
        });
        if (rtl.isEmpty()) {
            return "SUMMARY: no RTL files (.sv/.v) were provided — nothing to validate.";
        }
        String top = topModule(rtl);
        String rtlList = String.join(" ", rtl.keySet());
        StringBuilder report = new StringBuilder("Top module: ").append(top).append("\n\n");

        EdaRunner.Result lint = eda.run(rtl, "verilator --lint-only -Wall -Wno-DECLFILENAME"
                + " -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM --top-module " + top + " " + rtlList
                + " && echo 'LINT CLEAN'");
        report.append("== lint (Verilator) ==\n").append(lint.output()).append("\n\n");

        int simPassed = 0;
        List<String> simResults = new ArrayList<>();
        for (var tb : tbs.entrySet()) {
            String tbTop = firstModule(tb.getValue());
            Map<String, String> all = new LinkedHashMap<>(rtl);
            all.put(tb.getKey(), tb.getValue());
            EdaRunner.Result sim = eda.run(all, "iverilog -g2012 -s " + tbTop + " -o sim "
                    + rtlList + " " + tb.getKey() + " && timeout 60 vvp -n sim");
            boolean passed = sim.ok() && !sim.output().contains("FAIL")
                    && (sim.output().contains("ALL TESTS PASSED") || sim.output().contains("PASS"));
            if (passed) {
                simPassed++;
            }
            simResults.add(tb.getKey() + (passed ? " passed" : " FAILED"));
            report.append("== simulate ").append(tb.getKey()).append(" (Icarus) ==\n")
                    .append(sim.output()).append("\n\n");
        }

        EdaRunner.Result synth = eda.run(rtl, "yosys -q -p 'read_verilog -sv " + rtlList
                + "; synth -top " + top + "; check; tee -o stat.txt stat' >/dev/null 2>yosys.err;"
                + " s=$?; cat yosys.err; cat stat.txt 2>/dev/null; exit $s");
        report.append("== synthesize (Yosys) ==\n").append(synth.output()).append("\n\n");
        Matcher cells = CELLS.matcher(synth.output());
        String cellCount = cells.find() ? cells.group(1) : "?";

        boolean lintClean = lint.ok() && lint.output().contains("LINT CLEAN");
        report.append("SUMMARY: lint=").append(lintClean ? "clean" : "ERRORS")
                .append(", simulation=").append(tbs.isEmpty() ? "NO TESTBENCH"
                        : simPassed + "/" + tbs.size() + " passed " + simResults)
                .append(", synthesis=").append(synth.ok() ? "ok" : "FAILED")
                .append(", cells=").append(cellCount)
                .append(lintClean && synth.ok() && !tbs.isEmpty() && simPassed == tbs.size()
                        ? ", OVERALL PASS" : ", OVERALL FAIL");
        return report.toString();
    }

    /** The declared module no other RTL module instantiates (the last such, if several). */
    static String topModule(Map<String, String> rtl) {
        List<String> declared = new ArrayList<>();
        StringBuilder code = new StringBuilder();
        for (String src : rtl.values()) {
            String clean = COMMENTS.matcher(src).replaceAll(" ");
            code.append(clean).append('\n');
            Matcher m = MODULE_DECL.matcher(clean);
            while (m.find()) {
                declared.add(m.group(1));
            }
        }
        String all = code.toString();
        String top = declared.isEmpty() ? "top" : declared.getLast();
        for (String name : declared) {
            int uses = 0;
            Matcher m = Pattern.compile("\\b" + Pattern.quote(name) + "\\b").matcher(all);
            while (m.find()) {
                uses++;
            }
            if (uses == 1) { // only its own declaration
                top = name;
            }
        }
        return top;
    }

    static String firstModule(String src) {
        Matcher m = MODULE_DECL.matcher(COMMENTS.matcher(src).replaceAll(" "));
        return m.find() ? m.group(1) : "tb";
    }
}
