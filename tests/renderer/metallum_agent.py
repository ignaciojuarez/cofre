#!/usr/bin/env python3
"""Repair Air's pinned metallum_agent.jar and prove the vanilla 1.21.11 / 26.2 Metal gaps are closed."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import zipfile

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

SHIM_FIXTURE = r'''
package com.mojang.blaze3d.vulkan.glsl;
final class SpvUniformBuffer { }
final class SpvSampler { }
final class SpvVariable { }
'''

SIGNED_CLIENT_CLASS = r'''
package com.mojang.blaze3d.vulkan.glsl;
public final class ShaderCompileException extends RuntimeException { }
'''

SHIM_PROBE = r'''
import java.io.File;
import java.lang.reflect.Modifier;
import java.net.URL;
import java.net.URLClassLoader;
public final class ShimProbe {
  public static void main(String[] args) throws Exception {
    Class<?> shim = Class.forName("com.metallum.agent.CofreMetallumAgent");
    java.lang.reflect.Method forceVanilla = shim.getDeclaredMethod("maybeForceVanillaClassSet", ClassLoader.class);
    forceVanilla.setAccessible(true);
    forceVanilla.invoke(null, ShimProbe.class.getClassLoader());
    Class<?> air = Class.forName("com.metallum.agent.MetallumAgent", false,
        ShimProbe.class.getClassLoader());
    java.lang.reflect.Field irisBridge = air.getDeclaredField("gIrisBridge");
    irisBridge.setAccessible(true);
    if (!Boolean.FALSE.equals(irisBridge.get(null))) throw new AssertionError("Air Iris bridge stayed enabled");
    for (String name : new String[]{"SpvUniformBuffer", "SpvSampler", "SpvVariable"}) {
      Class<?> type = Class.forName("com.mojang.blaze3d.vulkan.glsl." + name);
      if (!Modifier.isPublic(type.getModifiers())) throw new AssertionError(name + " is not public");
      if (args.length > 0 && (type.getProtectionDomain().getCodeSource().getCodeSigners() == null
          || type.getProtectionDomain().getCodeSource().getCodeSigners().length != 1))
        throw new AssertionError(name + " did not keep the client signer");
    }
    if (args.length == 0) {
      Class.forName("com.mojang.blaze3d.vulkan.glsl.ShaderCompileException");
    } else {
      try (URLClassLoader client = new URLClassLoader(new URL[]{new File(args[0]).toURI().toURL()},
          ClassLoader.getSystemClassLoader())) {
        Class.forName("com.mojang.blaze3d.vulkan.glsl.ShaderCompileException", true, client);
      }
    }
    System.out.println("PASS: Cofre premain shim widens all Spv classes before definition");
    System.exit(0);
  }
}
'''

PREFERRED_GRAPHICS_API = r'''
package net.minecraft.client;
public final class PreferredGraphicsApi { }
'''

ROUTE_PROBE = r'''
public final class RouteProbe {
  public static void main(String[] args) throws Exception {
    Class.forName("net.minecraft.client.PreferredGraphicsApi");
    Class<?> metalDevice = Class.forName("com.metallum.client.metal.render.MetalDevice", false,
        RouteProbe.class.getClassLoader());
    for (java.lang.reflect.Field field : metalDevice.getDeclaredFields()) {
      if (field.getName().equals("genericVertexAttributeBuffer")) throw new AssertionError("Iris MetalDevice loaded");
    }
    System.out.println("METAL_DEVICE_VANILLA");
    System.out.println("ROUTE_PROBE_DONE");
    System.exit(0);
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


def run(*args, env=None):
    return subprocess.run([str(a) for a in args], capture_output=True, text=True, env=env)


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
    with zipfile.ZipFile(jar) as repaired_jar:
        manifest = repaired_jar.read("META-INF/MANIFEST.MF").decode()
        assert "Premain-Class: com.metallum.agent.CofreMetallumAgent" in manifest
        assert "Agent-Class: com.metallum.agent.CofreMetallumAgent" in manifest
        vanilla_device = repaired_jar.read("classes262/com/metallum/client/metal/render/MetalDevice.class")
        iris_device = repaired_jar.read("classes262iris/com/metallum/client/metal/render/MetalDevice.class")
        assert b"IrisMetalTerrainBridge" not in vanilla_device
        assert b"IrisMetalTerrainBridge" in iris_device
    again = run("python3", SCRIPT, jar)
    assert again.returncode == 0 and not again.stdout and jar.read_bytes() == repaired, "repair is not idempotent"
    java = java25()
    assert java, "needs a JDK 25 (brew install openjdk@25, or set JAVA_HOME)"
    (tree / "Probe.java").write_text(PROBE)
    probe = run(java, "-cp", jar, tree / "Probe.java", jar)
    assert probe.returncode == 0, probe.stdout + probe.stderr
    print(probe.stdout.strip())

    classes = tree / "classes"
    classes.mkdir()
    fixture = tree / "SpvUniformBuffer.java"
    fixture.write_text(SHIM_FIXTURE)
    shim_probe = tree / "ShimProbe.java"
    shim_probe.write_text(SHIM_PROBE)
    javac = java.with_name("javac")
    compiled = run(javac, "-d", classes, fixture, shim_probe)
    assert compiled.returncode == 0, compiled.stdout + compiled.stderr
    preferred_graphics_api = tree / "PreferredGraphicsApi.java"
    preferred_graphics_api.write_text(PREFERRED_GRAPHICS_API)
    route_probe = tree / "RouteProbe.java"
    route_probe.write_text(ROUTE_PROBE)
    route_compiled = run(javac, "-d", classes, preferred_graphics_api, route_probe)
    assert route_compiled.returncode == 0, route_compiled.stdout + route_compiled.stderr
    signed_source = tree / "ShaderCompileException.java"
    signed_source.write_text(SIGNED_CLIENT_CLASS)
    client_classes = tree / "client-classes"
    client_classes.mkdir()
    signed_compile = run(javac, "-d", client_classes, signed_source)
    assert signed_compile.returncode == 0, signed_compile.stdout + signed_compile.stderr
    keytool = java.with_name("keytool")
    keystore = tree / "cofre.p12"
    generated = run(keytool, "-genkeypair", "-alias", "cofre", "-keyalg", "RSA", "-keysize", "2048",
                    "-validity", "1", "-dname", "CN=Cofre", "-keystore", keystore,
                    "-storetype", "PKCS12", "-storepass", "changeit", "-keypass", "changeit", "-noprompt")
    assert generated.returncode == 0, generated.stdout + generated.stderr
    signed_jar = tree / "minecraft-client-signed.jar"
    jar_tool = java.with_name("jar")
    packed = run(jar_tool, "cf", signed_jar, "-C", client_classes, ".")
    assert packed.returncode == 0, packed.stdout + packed.stderr
    jarsigner = java.with_name("jarsigner")
    signed = run(jarsigner, "-keystore", keystore, "-storetype", "PKCS12", "-storepass", "changeit",
                 "-keypass", "changeit", signed_jar, "cofre")
    assert signed.returncode == 0, signed.stdout + signed.stderr
    classpath = str(jar) + os.pathsep + str(signed_jar) + os.pathsep + str(classes)
    shim = run(java, "--add-opens=java.base/java.lang=ALL-UNNAMED", "-Dmetallum.mc.version=26.2",
               "-javaagent:" + str(jar), "-cp", classpath, "ShimProbe")
    assert shim.returncode == 0, shim.stdout + shim.stderr
    assert "Cofre Spv preload code source:" in shim.stdout and "signers=1" in shim.stdout
    assert "Cofre Spv preload defined: com/mojang/blaze3d/vulkan/glsl/SpvUniformBuffer" in shim.stdout
    assert "Cofre Spv preload defined: com/mojang/blaze3d/vulkan/glsl/SpvSampler" in shim.stdout
    assert "Cofre Spv preload defined: com/mojang/blaze3d/vulkan/glsl/SpvVariable" in shim.stdout
    assert "PASS: Cofre premain shim widens all Spv classes" in shim.stdout

    route = run(java, "--add-opens=java.base/java.lang=ALL-UNNAMED", "-Dmetallum.mc.version=26.2",
                "-javaagent:" + str(jar), "-cp", str(jar) + os.pathsep + str(classes), "RouteProbe",
                env=dict(os.environ, AMETHYST_RENDERER="metal"))
    assert route.returncode == 0, route.stdout + route.stderr
    routes = [line for line in route.stdout.splitlines() if "[CLASSSET-ROUTE]" in line]
    assert len(routes) == 1 and "prefix='classes262/'" in routes[0], route.stdout
    assert "prefix='classes262iris/'" not in route.stdout, route.stdout
    assert "DEFINE-OK summary:" in route.stdout and "prefix=classes262/" in route.stdout, route.stdout
    assert "METAL_DEVICE_VANILLA" in route.stdout, route.stdout
    assert "ROUTE_PROBE_DONE" in route.stdout, route.stdout
    print(route.stdout.strip())
    print(shim.stdout.strip())

    game_root = tree / "game"
    game_jar = game_root / "versions" / "26.2" / "26.2.jar"
    game_jar.parent.mkdir(parents=True)
    shutil.copy(signed_jar, game_jar)
    path_env = dict(os.environ, POJAV_GAME_DIR=str(game_root))
    path_shim = run(java, "--add-opens=java.base/java.lang=ALL-UNNAMED", "-Dmetallum.mc.version=26.2",
                    "-javaagent:" + str(jar), "-cp", str(jar) + os.pathsep + str(classes),
                    "ShimProbe", signed_jar, env=path_env)
    assert path_shim.returncode == 0, path_shim.stdout + path_shim.stderr
    assert "signers=1" in path_shim.stdout
    print(path_shim.stdout.strip())
