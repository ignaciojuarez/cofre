package com.metallum.agent;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.IllegalClassFormatException;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;
import java.util.Set;

/**
 * Installs Cofre's Spv access widener before Air's agent starts.
 *
 * Air's transformer only sees classes defined after premain registers it. On vanilla 26.2 the
 * package-private Spv records can already be loaded by the game loader, so that transformer never
 * gets a chance to widen them. This shim is first in the transformer chain, before Air's premain
 * can load any of the renderer classes. Class redefinition cannot change a JVM class's modifiers,
 * so registering before Air is the required ordering guarantee.
 */
public final class CofreMetallumAgent {
    private static final Set<String> ACCESSIBLE_CLASSES = Set.of(
            "com/mojang/blaze3d/vulkan/glsl/SpvUniformBuffer",
            "com/mojang/blaze3d/vulkan/glsl/SpvSampler",
            "com/mojang/blaze3d/vulkan/glsl/SpvVariable");

    private CofreMetallumAgent() {
    }

    public static void premain(String args, Instrumentation instrumentation) {
        install(instrumentation);
        MetallumAgent.premain(args, instrumentation);
    }

    public static void agentmain(String args, Instrumentation instrumentation) {
        premain(args, instrumentation);
    }

    private static void install(Instrumentation instrumentation) {
        instrumentation.addTransformer(new AccessTransformer(), true);
        System.out.println("[MetallumAgent] Cofre Spv access widener installed (before Air premain)");
    }

    private static final class AccessTransformer implements ClassFileTransformer {
        @Override
        public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined,
                ProtectionDomain protectionDomain, byte[] classfileBuffer) throws IllegalClassFormatException {
            if (!ACCESSIBLE_CLASSES.contains(className) || classfileBuffer == null) {
                return null;
            }
            int accessOffset = accessFlagsOffset(classfileBuffer);
            if (accessOffset < 0) {
                return null;
            }
            int access = readUnsignedShort(classfileBuffer, accessOffset);
            if ((access & 0x0001) != 0) {
                return null;
            }
            byte[] widened = classfileBuffer.clone();
            int publicAccess = (access & ~0x0006) | 0x0001;
            widened[accessOffset] = (byte) (publicAccess >>> 8);
            widened[accessOffset + 1] = (byte) publicAccess;
            System.out.println("[MetallumAgent] accesswidener applied: " + className
                    + " (Cofre preload shim)");
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
