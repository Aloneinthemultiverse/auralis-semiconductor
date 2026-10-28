package ai.auralis.semiconductor.library;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Set;
import java.util.stream.Stream;

import org.springframework.ai.mcp.annotation.McpTool;
import org.springframework.ai.mcp.annotation.McpToolParam;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Read-only access to finished designs in the designs folder (README, design log,
 * RTL, testbenches, constraints), so clients such as Auralis VSD can show what was
 * built and how it was verified. Paths are confined to the design's own folder.
 */
@Component
public class DesignLibrary {

    private static final Set<String> TEXT = Set.of(".sv", ".svh", ".v", ".md", ".sdc", ".py", ".sp", ".sh", ".tcl", ".json", ".txt");
    private static final Set<String> SKIP_DIRS = Set.of("obj_full", "obj_dir", "build", "__pycache__", ".git");
    private static final int MAX_BYTES = 300_000;

    private final Path root;

    public DesignLibrary(@Value("${semiconductor.designs-dir:../designs}") String root) {
        this.root = Path.of(root).toAbsolutePath().normalize();
    }

    @McpTool(name = "design_list", description = "Finished designs in the library, with the title line of each README.")
    public String list() throws IOException {
        if (!Files.isDirectory(root)) {
            return "No designs folder at " + root;
        }
        StringBuilder sb = new StringBuilder();
        try (Stream<Path> dirs = Files.list(root)) {
            for (Path d : dirs.filter(Files::isDirectory).sorted().toList()) {
                Path readme = d.resolve("README.md");
                String title = Files.exists(readme)
                        ? Files.readAllLines(readme, StandardCharsets.UTF_8).stream().filter(l -> l.startsWith("#"))
                                .findFirst().orElse("").replaceFirst("^#+\\s*", "")
                        : "";
                sb.append(d.getFileName()).append('\t').append(title).append('\n');
            }
        }
        return sb.toString();
    }

    @McpTool(name = "design_files", description = "Source and documentation files of a design (relative path and size in bytes), one per line.")
    public String files(@McpToolParam(description = "Design folder name, e.g. edge_ai_soc") String design) throws IOException {
        Path dir = designDir(design);
        if (dir == null) {
            return "Unknown design: " + design;
        }
        StringBuilder sb = new StringBuilder();
        try (Stream<Path> all = Files.walk(dir)) {
            List<Path> files = all.filter(Files::isRegularFile)
                    .filter(p -> TEXT.contains(ext(p)))
                    .filter(p -> dir.relativize(p).toString().replace('\\', '/').chars().filter(ch -> ch == '/').count() <= 3)
                    .filter(p -> SKIP_DIRS.stream().noneMatch(s -> dir.relativize(p).toString().replace('\\', '/').contains(s + "/")))
                    .sorted().toList();
            for (Path p : files) {
                sb.append(dir.relativize(p).toString().replace('\\', '/')).append('\t').append(Files.size(p)).append('\n');
            }
        }
        return sb.toString();
    }

    @McpTool(name = "design_read", description = "Text of one file of a design (README.md, LESSONS.md, rtl/npu_pe.sv, ...), up to 300 KB.")
    public String read(@McpToolParam(description = "Design folder name") String design,
                       @McpToolParam(description = "Path inside the design, as listed by design_files") String path) throws IOException {
        Path dir = designDir(design);
        if (dir == null) {
            return "Unknown design: " + design;
        }
        Path p = dir.resolve(path).normalize();
        if (!p.startsWith(dir) || !Files.isRegularFile(p) || !TEXT.contains(ext(p))) {
            return "Not a readable design file: " + path;
        }
        byte[] b = Files.readAllBytes(p);
        String s = new String(b, 0, Math.min(b.length, MAX_BYTES), StandardCharsets.UTF_8);
        return b.length > MAX_BYTES ? s + "\n… (truncated)" : s;
    }

    private Path designDir(String design) {
        if (design == null || !design.matches("[A-Za-z0-9_.-]+")) {
            return null;
        }
        Path d = root.resolve(design).normalize();
        return d.startsWith(root) && Files.isDirectory(d) ? d : null;
    }

    private static String ext(Path p) {
        String n = p.getFileName().toString();
        int i = n.lastIndexOf('.');
        return i < 0 ? "" : n.substring(i).toLowerCase();
    }
}
