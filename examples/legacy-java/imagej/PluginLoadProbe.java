import ij.io.PluginClassLoader;
import ij.plugin.PlugIn;
import java.io.File;

/** Local probe: use the inspected upstream loader, never initialize or instantiate the plugin. */
public final class PluginLoadProbe {
    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("One compiled-plugin directory required");
        File directory = new File(args[0]).getCanonicalFile();
        try (PluginClassLoader loader = new PluginClassLoader(directory.getPath())) {
            Class<?> plugin = Class.forName("JavaScriptEvaluator", false, loader);
            if (plugin.getClassLoader() != loader) throw new IllegalStateException("Plugin was not loaded by the upstream plugin loader");
            if (!PlugIn.class.isAssignableFrom(plugin)) throw new IllegalStateException("Not an ImageJ plugin");
            File origin = new File(plugin.getProtectionDomain().getCodeSource().getLocation().toURI()).getCanonicalFile();
            if (!origin.equals(directory)) throw new IllegalStateException("Unexpected class source: " + origin);
            System.out.println("PASS: genuine loose class resolved by upstream ImageJ PluginClassLoader");
            System.out.println("Plugin initialized=false; instantiated=false; run invoked=false");
        }
    }
}
