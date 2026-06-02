package com.example.demo;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class VisitController {

    private final JdbcTemplate jdbc;

    // Constructor injection: Spring auto-wires the JdbcTemplate that
    // spring-boot-starter-jdbc builds from the DB_* env vars.
    public VisitController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping("/")
    public String home() {
        // Idempotent: safe to call on every request, creates the table once.
        jdbc.execute("CREATE TABLE IF NOT EXISTS visits ("
                + "id INT AUTO_INCREMENT PRIMARY KEY, "
                + "ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
        jdbc.update("INSERT INTO visits (ts) VALUES (NOW())");
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM visits", Integer.class);

        return "<html><body style='font-family:sans-serif;text-align:center;margin-top:60px'>"
                + "<h1>Java + MySQL on Kubernetes</h1>"
                + "<p>Database connection: <b style='color:#0E8A16'>OK</b></p>"
                + "<p>Total visits: <b>" + count + "</b></p>"
                + "<hr style='width:200px'><small>served by Spring Boot</small>"
                + "</body></html>";
    }

    // Lightweight endpoint for the readiness probe (no DB hit).
    @GetMapping("/health")
    public String health() {
        return "OK";
    }
}
