package com.metallum.agent;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Cofre-owned stand-in for the class Air's Minecraft 1.21.11 Metal path calls but never ships
 * (MetalDevice.prepareShaderSource -> ShaderVersionBump.bump). Metallum compiles GLSL to SPIR-V for
 * OpenGL, and glslang rejects desktop shaders below #version 330 there ("Desktop shaders for OpenGL
 * SPIR-V require version 330 or higher"). Vanilla 1.21.11 shaders are already 330 and pass through
 * unchanged; older resource-pack shaders (#version 150) are raised to 330 core.
 * Built into Air's metallum_agent.jar by scripts/repair-metallum-agent.py.
 */
public final class ShaderVersionBump {
    private static final int MINIMUM = 330;
    private static final Pattern VERSION = Pattern.compile("(?m)^[ \\t]*#version[ \\t]+(\\d+)[^\\r\\n]*");

    private ShaderVersionBump() {
    }

    public static String bump(String source) {
        if (source == null) {
            return null;
        }
        Matcher version = VERSION.matcher(source);
        if (!version.find() || version.group(1).length() > 3 || Integer.parseInt(version.group(1)) >= MINIMUM) {
            return source;
        }
        return source.substring(0, version.start()) + "#version " + MINIMUM + " core" + source.substring(version.end());
    }
}
