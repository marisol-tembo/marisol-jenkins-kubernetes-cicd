package com.marisol.demo;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {

  @GetMapping("/health")
  public Map<String, String> health() {
    return Map.of("status", "UP");
  }

  @GetMapping("/api/info")
  public Map<String, String> info() {
    return Map.of(
        "service", "jenkins-k8s-demo-app",
        "status", "ok",
        "message", "Hello from Jenkins -> Ansible -> EKS"
    );
  }
}
