package edu.jhu.cs.bigbang.eclipse;

import java.io.File;
import java.net.URL;
import org.eclipse.jface.resource.ImageDescriptor;
import org.eclipse.ui.plugin.AbstractUIPlugin;
import org.osgi.framework.BundleContext;

import edu.jhu.cs.bigbang.eclipse.toploop.TopLoopView;


/**
 * 
 * The default activator generated by Eclipse.
 * It is instantiated when the platform starts and will be used
 * by the whole plug-in environment.
 * 
 * @author Keeratipong Ukachoke <kukacho1@jhu.edu>
 *
 */
public class Activator extends AbstractUIPlugin {

	public static final String PLUGIN_ID = "bigbang.activator";
	
	private static Activator plugin;
	private final String pluginDirectory;
	private TopLoopView topLoopView;

	/**
	 * The default constructor.
	 * 1. Set the current directory
	 */
	public Activator() {
		File f = new File("");
		this.pluginDirectory = f.getAbsolutePath();
	}

	@Override
	public void start(BundleContext context) throws Exception {
		super.start(context);
		plugin = this;
	}

	@Override
	public void stop(BundleContext context) throws Exception {
		plugin = null;
		super.stop(context);
	}

	/**
	 * Returns the shared instance
	 *
	 * @return the shared instance
	 */
	public static Activator getDefault() {
		return plugin;
	}
	
	/**
	 * Return the shared top loop view
	 * @return The shared top loop view
	 */
	public TopLoopView getTopLoopView() {
		return topLoopView;
	}

	/**
	 * Set the shared top loop view
	 * @param topLoopView The shared top loop view
	 */
	public void setTopLoopView(TopLoopView topLoopView) {
		this.topLoopView = topLoopView;
	}

	/**
	 * Get the plug-in directory
	 * @return The plug-in directory
	 */
	public String getPluginDirectory() {
		return plugin.pluginDirectory;
	}

	/**
	 * Get the installed directory
	 * @return The installed directory
	 */
	public URL getInstallURL() {
		return plugin.getBundle().getEntry("/");
	}

	/**
	 * Returns an image descriptor for the image file at the given
	 * plug-in relative path
	 *
	 * @param path The path
	 * @return The image descriptor
	 */
	public static ImageDescriptor getImageDescriptor(String path) {
		return imageDescriptorFromPlugin(PLUGIN_ID, path);
	}
}
