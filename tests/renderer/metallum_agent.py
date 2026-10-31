#!/usr/bin/env python3
"""Repair Air's pinned metallum_agent.jar and prove the vanilla 1.21.11 / 26.2 Metal gaps are closed."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/repair-metallum-agent.py"
PINNED = ROOT / "upstream/air/JavaApp/libs/others/metallum_agent.jar"

# Mirrors the agent: Fabric stubs + the class set's Metallum go into a child "game" loader whose parent
# (the app loader) has the agent jar; MetalDevice's shader prep must reach the root ShaderVersionBump.
PROBE = r'''
import java.net.*; import java.util.zip.*;
public class Probe {
  static class Game extends URLClassLoader {
    Game(ClassLoader parent) { super(new URL[0], parent); }
    void def(ZipFile z, String prefix, String name) throws Exception {
      ZipEntry e = z.getEntry(prefix + name + ".class");
      if (e != null) { byte[] b = z.getInputStream(e).readAllBytes(); defineClass(name.replace('/', '.'), b, 0, b.length); }
    }
  }
  static void check(boolean ok, String what) { if (!ok) throw new AssertionError(what); }
  public static void main(String[] a) throws Exception {
    ZipFile z = new ZipFile(a[0]);
    for (String prefix : new String[]{"classes12111_1_21_11/", "classes262iris/"}) {
      Game g = new Game(Probe.class.getClassLoader());
      for (String s : new String[]{"net/fabricmc/api/ModInitializer", "net/fabricmc/api/EnvType",
          "net/fabricmc/api/Environment", "net/fabricmc/loader/api/entrypoint/PreLaunchEntrypoint", "com/metallum/Metallum"})
        g.def(z, prefix, s);
      Class<?> metallum = Class.forName("com.metallum.Metallum", false, g);
      check(metallum.getClassLoader() == g, prefix + " Metallum fell back to the app loader");
      if (prefix.startsWith("classes12111")) Class.forName("com.metallum.Metallum", true, g);  // new NopLogger()
    }
    Class<?> bump = Class.forName("com.metallum.agent.ShaderVersionBump");
    java.lang.reflect.Method m = bump.getMethod("bump", String.class);
    check(m.invoke(null, "#version 150\nvoid main(){}").equals("#version 330 core\nvoid main(){}"), "150 not raised");
    check(m.invoke(null, "  #version 120 compatibility\r\nx").equals("#version 330 core\r\nx"), "profile not replaced");
    for (String same : new String[]{"#version 330\nx", "#version 450 core\nx", "void main(){}", "#version 99999999999\n"})
      check(m.invoke(null, same).equals(same), "changed: " + same);
    check(m.invoke(null, (Object) null) == null, "null");
    System.out.println("PASS: 1.21.11 and 26.2 Metallum load in the game loader; ShaderVersionBump resolves");
  }
}
'''


def java25():
    """Air's class sets are Java 25 class files, like the game's runtime on the device."""
    found = subprocess.run(["/usr/libexec/java_home", "-v", "25+"], capture_output=True, text=True)
    for home in (found.stdout.strip() if found.returncode == 0 else "", "/opt/homebrew/opt/openjdk@25",
                 os.environ.get("JAVA_HOME", "")):
        java = Path(home) / "bin/java"
        version = re.search(r'version "(\d+)', run(java, "-version").stderr) if home and java.exists() else None
        if version and int(version.group(1)) >= 25:
            return java
    return None


def run(*args):
    return subprocess.run([str(a) for a in args], capture_output=True, text=True)


with tempfile.TemporaryDirectory(prefix="cofre-metallum-test-") as directory:
    tree = Path(directory)
    jar = tree / "metallum_agent.jar"
    shutil.copy(PINNED, jar)
    before = run("python3", SCRIPT, "--check", jar)
    assert before.returncode == 1, "pinned Air jar no longer has the known gaps; revisit the repair"
    for gap in ("ShaderVersionBump", "classes262iris/com/metallum/Metallum -> class net/fabricmc/api/ModInitializer",
                "private com/metallum/agent/NopLogger.<init>()V"):
        assert gap in before.stderr, f"--check missed: {gap}\n{before.stderr}"
    first = run("python3", SCRIPT, jar)
    assert first.returncode == 0, first.stdout + first.stderr
    repaired = jar.read_bytes()
    again = run("python3", SCRIPT, jar)
    assert again.returncode == 0 and not again.stdout and jar.read_bytes() == repaired, "repair is not idempotent"
    java = java25()
    assert java, "needs a JDK 25 (brew install openjdk@25, or set JAVA_HOME)"
    (tree / "Probe.java").write_text(PROBE)
    probe = run(java, "-cp", jar, tree / "Probe.java", jar)
    assert probe.returncode == 0, probe.stdout + probe.stderr
    print(probe.stdout.strip())
