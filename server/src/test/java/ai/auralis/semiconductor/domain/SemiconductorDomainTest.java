package ai.auralis.semiconductor.domain;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.LinkedHashMap;
import java.util.Map;

import org.junit.jupiter.api.Test;

class SemiconductorDomainTest {

    @Test
    void topIsTheModuleNobodyInstantiates() {
        Map<String, String> rtl = new LinkedHashMap<>();
        rtl.put("top.sv", "module top(input clk); adder u_add(.a(1'b0)); endmodule");
        rtl.put("adder.sv", "// module fake in a comment\nmodule adder(input a); endmodule");
        assertThat(SemiconductorDomain.topModule(rtl)).isEqualTo("top");
    }

    @Test
    void firstModuleIgnoresComments() {
        assertThat(SemiconductorDomain.firstModule("/* module x */ module tb_top; endmodule"))
                .isEqualTo("tb_top");
    }
}
