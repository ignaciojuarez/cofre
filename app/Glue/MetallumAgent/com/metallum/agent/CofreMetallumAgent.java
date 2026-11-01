package com.metallum.agent;

import java.io.IOException;
import java.io.InputStream;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.IllegalClassFormatException;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.security.ProtectionDomain;
import java.util.Set;

/**
 * Installs Cofre's Spv access widener before Air's agent starts.
 *
 * Air's transformer only sees classes defined after premain registers it. On vanilla 26.2 the
 * package-private Spv records can already be loaded by the game loader, so that transformer never
 * gets a chance to widen them. This shim is first in the transformer chain, before Air's premain
 * can load any of the renderer classes. The 26.2 class set is also defined directly into the game
 * loader before Air starts: this covers the PojavClassLoader path that bypasses instrumentation.
 */
public final class CofreMetallumAgent {
    private static final Set<String> ACCESSIBLE_CLASSES = Set.of(
            "com/mojang/blaze3d/vulkan/glsl/SpvUniformBuffer",
            "com/mojang/blaze3d/vulkan/glsl/SpvSampler",
            "com/mojang/blaze3d/vulkan/glsl/SpvVariable");
    private static final String[] SPV_CLASSES = {
            "com/mojang/blaze3d/vulkan/glsl/SpvUniformBuffer",
            "com/mojang/blaze3d/vulkan/glsl/SpvSampler",
            "com/mojang/blaze3d/vulkan/glsl/SpvVariable"};

    private CofreMetallumAgent() {
    }

    public static void premain(String args, Instrumentation instrumentation) {
        install(instrumentation);
        logLoadedSpv(instrumentation, "before preload");
        preloadSpvClasses();
        logLoadedSpv(instrumentation, "after preload");
        MetallumAgent.premain(args, instrumentation);
    }

    public static void agentmain(String args, Instrumentation instrumentation) {
        premain(args, instrumentation);
    }

    private static void install(Instrumentation instrumentation) {
        instrumentation.addTransformer(new AccessTransformer(), true);
        System.out.println("[MetallumAgent] Cofre Spv access widener installed (before Air premain)");
    }

    private static void logLoadedSpv(Instrumentation instrumentation, String stage) {
        for (Class<?> type : instrumentation.getAllLoadedClasses()) {
            String name = type.getName().replace('.', '/');
            if (ACCESSIBLE_CLASSES.contains(name)) {
                System.out.println("[MetallumAgent] Cofre Spv " + stage + ": " + name
                        + " loader=" + type.getClassLoader() + " modifiers=0x"
                        + Integer.toHexString(type.getModifiers()));
            }
        }
    }

    private static void preloadSpvClasses() {
        String prefix = classSetPrefix();
        if (prefix == null) {
            System.out.println("[MetallumAgent] Cofre Spv preload skipped: no 26.2 class set for mcVersion="
                    + System.getProperty("metallum.mc.version", ""));
            return;
        }
        ClassLoader loader = ClassLoader.getSystemClassLoader();
        if (loader == null) {
            System.out.println("[MetallumAgent] Cofre Spv preload skipped: system loader unavailable");
            return;
        }
        String modLoader = detectedModLoader(loader);
        if (modLoader != null) {
            System.out.println("[MetallumAgent] Cofre Spv preload skipped: mod loader " + modLoader
                    + " owns class definition");
            return;
        }
        try {
            Method defineClass = ClassLoader.class.getDeclaredMethod("defineClass", String.class,
                    byte[].class, int.class, int.class, ProtectionDomain.class);
            defineClass.setAccessible(true);
            for (String internalName : SPV_CLASSES) {
                String resource = "/" + prefix + internalName + ".class";
                byte[] original = readResource(resource);
                if (original == null) {
                    System.out.println("[MetallumAgent] Cofre Spv preload missing resource: " + prefix + internalName);
                    continue;
                }
                byte[] widened = AccessTransformer.widen(original);
                if (widened == null) {
                    System.out.println("[MetallumAgent] Cofre Spv preload invalid class: " + internalName);
                    continue;
                }
                try {
                    defineClass.invoke(loader, internalName.replace('/', '.'), widened, 0, widened.length, null);
                    System.out.println("[MetallumAgent] Cofre Spv preload defined: " + internalName
                            + " loader=" + loader);
                } catch (InvocationTargetException failure) {
                    Throwable cause = failure.getCause();
                    if (cause instanceof LinkageError) {
                        System.out.println("[MetallumAgent] Cofre Spv preload skipped already defined: "
                                + internalName + " loader=" + loader + " cause=" + cause);
                    } else {
                        System.err.println("[MetallumAgent] Cofre Spv preload failed: " + internalName
                                + " cause=" + cause);
                    }
                }
            }
        } catch (Throwable failure) {
            System.err.println("[MetallumAgent] Cofre Spv preload unavailable: " + failure);
        }
    }

    private static String classSetPrefix() {
        String version = System.getProperty("metallum.mc.version", "");
        if (version.startsWith("26.2")) {
            return "classes262iris/";
        }
        return null;
    }

    private static String detectedModLoader(ClassLoader loader) {
        String[] candidates = {
                "net.fabricmc.loader.api.FabricLoader",
                "net.neoforged.fml.loading.FMLLoader",
                "cpw.mods.modlauncher.Launcher"};
        for (String candidate : candidates) {
            try {
                Class.forName(candidate, false, loader);
                return candidate;
            } catch (ClassNotFoundException | LinkageError ignored) {
                // Vanilla has none of the loader entry points. Keep probing the known loaders.
            }
        }
        return null;
    }

    private static byte[] readResource(String resource) {
        try (InputStream stream = CofreMetallumAgent.class.getResourceAsStream(resource)) {
            return stream == null ? null : stream.readAllBytes();
        } catch (IOException failure) {
            return null;
        }
    }

    private static final class AccessTransformer implements ClassFileTransformer {
        @Override
        public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined,
                ProtectionDomain protectionDomain, byte[] classfileBuffer) throws IllegalClassFormatException {
            String normalizedName = className == null ? null : className.replace('.', '/');
            if (normalizedName != null && normalizedName.contains("glsl/Spv")) {
                System.out.println("[MetallumAgent] Cofre Spv transformer saw: " + className
                        + " normalized=" + normalizedName + " loader=" + loader
                        + " redefining=" + classBeingRedefined + " bytes="
                        + (classfileBuffer == null ? 0 : classfileBuffer.length));
            }
            if (!ACCESSIBLE_CLASSES.contains(normalizedName) || classfileBuffer == null) {
                return null;
            }
            byte[] widened = widen(classfileBuffer);
            if (widened == null) {
                return null;
            }
            if (widened == classfileBuffer) {
                return null;
            }
            System.out.println("[MetallumAgent] accesswidener applied: " + className
                    + " (Cofre preload shim)");
            return widened;
        }

        private static byte[] widen(byte[] classfileBuffer) {
            int accessOffset = accessFlagsOffset(classfileBuffer);
            if (accessOffset < 0) {
                return null;
            }
            int access = readUnsignedShort(classfileBuffer, accessOffset);
            if ((access & 0x0001) != 0) {
                return classfileBuffer;
            }
            byte[] widened = classfileBuffer.clone();
            int publicAccess = (access & ~0x0006) | 0x0001;
            widened[accessOffset] = (byte) (publicAccess >>> 8);
            widened[accessOffset + 1] = (byte) publicAccess;
            return widened;
        }

        private static int readUnsignedShort(byte[] bytes, int offset) {
            if (offset < 0 || bytes.length < offset + 2) {
                return 0;
            }
            return ((bytes[offset] & 0xff) << 8) | (bytes[offset + 1] & 0xff);
        }

        private static int accessFlagsOffset(byte[] bytes) {
            if (bytes.length < 10 || bytes[0] != (byte) 0xca || bytes[1] != (byte) 0xfe
                    || bytes[2] != (byte) 0xba || bytes[3] != (byte) 0xbe) {
                return -1;
            }
            int count = readUnsignedShort(bytes, 8);
            int offset = 10;
            for (int index = 1; index < count; index++) {
                if (offset >= bytes.length) {
                    return -1;
                }
                int tag = bytes[offset++] & 0xff;
                int size;
                switch (tag) {
                    case 1: // Utf8
                        size = 2 + readUnsignedShort(bytes, offset);
                        break;
                    case 3: // Integer
                    case 4: // Float
                    case 9: // Fieldref
                    case 10: // Methodref
                    case 11: // InterfaceMethodref
                    case 12: // NameAndType
                    case 17: // Dynamic
                    case 18: // InvokeDynamic
                        size = 4;
                        break;
                    case 5: // Long
                    case 6: // Double
                        size = 8;
                        index++;
                        break;
                    case 7: // Class
                    case 8: // String
                    case 16: // MethodType
                    case 19: // Module
                    case 20: // Package
                        size = 2;
                        break;
                    case 15: // MethodHandle
                        size = 3;
                        break;
                    default:
                        return -1;
                }
                offset += size;
                if (offset > bytes.length) {
                    return -1;
                }
            }
            return offset;
        }
    }
}
