package ai.auralis.semiconductor.eda;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Runs a shell script over a set of source files inside the {@code auralis-eda}
 * container (Verilator, Icarus Verilog, Yosys): throwaway, no network, capped
 * CPU and memory.
 */
@Component
public class EdaRunner {

    public record Result(int exitCode, String output) {

        public boolean ok() {
            return exitCode == 0;
        }
    }

    private static final int MAX_OUTPUT = 12000;

    private final String image;
    private final Duration timeout;
    private final Path workRoot = Path.of(System.getProperty("java.io.tmpdir"), "auralis-eda");

    public EdaRunner(@Value("${semiconductor.eda-image}") String image,
                     @Value("${semiconductor.timeout}") Duration timeout) {
        this.image = image;
        this.timeout = timeout;
    }

    public Result run(Map<String, String> files, String script) {
        Path dir = workRoot.resolve(UUID.randomUUID().toString());
        try {
            Files.createDirectories(dir);
            for (var f : files.entrySet()) {
                Path target = dir.resolve(f.getKey()).normalize();
                if (!target.startsWith(dir)) {
                    return new Result(2, "rejected file name: " + f.getKey());
                }
                Files.createDirectories(target.getParent());
                Files.writeString(target, f.getValue(), StandardCharsets.UTF_8);
            }
            Process p = new ProcessBuilder(List.of("docker", "run", "--rm", "--network", "none",
                    "--memory", "2g", "--cpus", "2", "-v", dir.toAbsolutePath() + ":/work",
                    "-w", "/work", image, "sh", "-c", script))
                    .redirectErrorStream(true).start();
            if (!p.waitFor(timeout.toSeconds(), TimeUnit.SECONDS)) {
                p.destroyForcibly();
                return new Result(124, "timed out after " + timeout.toSeconds() + "s");
            }
            String out = new String(p.getInputStream().readAllBytes(), StandardCharsets.UTF_8).strip();
            if (out.length() > MAX_OUTPUT) {
                out = out.substring(0, MAX_OUTPUT) + "\n… (truncated)";
            }
            return new Result(p.exitValue(), out);
        } catch (IOException ex) {
            return new Result(127, "could not run the EDA container (is Docker running and the "
                    + image + " image built?): " + ex.getMessage());
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            return new Result(130, "interrupted");
        } finally {
            try (var walk = Files.walk(dir)) {
                walk.sorted(Comparator.reverseOrder()).forEach(x -> x.toFile().delete());
            } catch (IOException ignored) {
                // best-effort temp cleanup
            }
        }
    }
}
