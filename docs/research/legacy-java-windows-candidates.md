# Public legacy Java / Windows onboarding candidates

## Conclusion

**No exact intersection was verified:** a real consuming application with multiple YAJSW Windows services **and** a supplied `.bat → javac → loose plugin .class → dynamic loader` deployment path.

Use two independent real fixtures rather than inventing that intersection:

1. **WSO2 Enterprise Integrator 6.6.0** is the strongest **multi-service consuming application**: first-party Windows instructions explicitly support multiple profiles under YAJSW, separate installation trees, and a modular Carbon/OSGi runtime. Its extensions are predominantly packaged bundles; no direct `javac` batch build was found.
2. **ImageJ 1.51u** is the strongest **genuine loose-class plugin fixture**: a five-line Windows batch builds loose classes, and source explicitly discovers, loads, and invokes external `.class` plugins. It is a desktop application, **not a verified YAJSW service deployment**. The batch builds built-in classes, not a supplied external-plugin deployment pipeline.
3. **eXist-db 3.6.1** is the strongest **self-contained legacy YAJSW source tree**: checked-in wrapper scripts/configuration/dependencies, Ant batch build, scattered extension libraries, and a plugin manager. Importantly, its YAJSW adapter really is compiled to and loaded from a loose class directory, but that adapter is **not an external plugin framework**, and only one service configuration is supplied.
4. **YAJSW's own source/samples** are a reference/control, not a consuming application candidate.

This is source inspection only. No builds, binaries, batch scripts, application launches, or service operations were executed; no onboarding implementation or test success is claimed.

## Requirement matrix

**C** = confirmed by inspected source/first-party documentation; **A** = absent from the inspected pinned scripts/configuration or demonstrated default route; **U** = unverified. An A is scoped, not a claim that no historical/custom deployment ever existed. “Multiple services” means Windows SCM services, not Java threads, OSGi services, or multiple children of one wrapper service.

| Candidate | YAJSW Windows consumer | Multiple Windows services | Dynamic Java plugin mechanism | Direct `javac` in supplied `.bat` | Loose external plugin classes loaded directly | Scattered scripts/dependency locations | Explicit SCM dependency graph |
|---|---|---|---|---|---|---|---|
| WSO2 EI 6.6.0 | C: official deployment recipe | C: supported multi-profile deployment; actual installed count U | C: Carbon/Equinox bundles | A: 42 batch files inspected | U: inspected plugin route uses JAR bundles, not loose plugins | C: profile trees, dropins, patches, lib and components | A: inspected wrapper recipe has no dependency entries; runtime graph U |
| eXist-db 3.6.1 | C: application-specific adapter and config | A: one generated service name/config; multi-instance deployment U | C: reflection/SPI plugin manager; live hot replacement U | A: 23 batch files inspected; compilation delegated to Ant | U: loose YAJSW adapter C, but external plugin path not established | C: extension libs, main libs, vendored wrapper libs and scripts | A: dependency property only commented out |
| ImageJ 1.51u | U: no YAJSW artifact in inspected tree | U: no Windows service recipe in inspected tree | C: plugin discovery, loader reset and invocation | C: `compile.bat` lines 1–4 | C: plugin directory/subdirectory URLs plus `.class` discovery | C: built-in packages, external plugin directories and JARs; batch sprawl A (two batch files) | U: no service configuration found |
| YAJSW pinned mirror | A: this is the wrapper itself | C: general capability, **not** a verified application's service topology | U: no consuming plugin framework established; Equinox sample is JAR-based | A: 25 batch files inspected | U: no loose external-plugin deployment established | C: wrapper/samples/local library layout | C: supported parameter; sample dependency is commented, not an application graph |

## 1. WSO2 Enterprise Integrator 6.6.0 — strongest multiple-service application

**Repository:** <https://github.com/wso2/product-ei>

**Pinned snapshot:** tag `v6.6.0` resolves to `bfdf341ab6dcfccce35c88b8a1567604f07ba8f5` ([commit API][ei-pin], [tree API][ei-tree]). The product's `pom.xml` line 1696 selects Carbon Kernel **4.5.3**; that dependency's tag `v4.5.3` resolves to `e07e00f16b91983e679d04f80aeba67fb08ebe39` ([EI POM][ei-pom], [kernel commit API][kernel-pin]). Do not substitute the moving `4.5.x` branch when reproducing this inspection.

### Evidence

- **YAJSW and service multiplicity:** the version-specific [EI 6.6.0 Windows-service guide][ei-windows] says “If you are running multiple profiles as Windows services, a separate copy of the server pack should be used for each profile,” specifically to avoid file locking/concurrency problems. It lists **four profile types** and corresponding `carbon_home`: ESB (root), business process (`wso2/business-process`), broker (`wso2/broker`), analytics (`wso2/analytics`). This confirms supported multiplicity, **not four services automatically installed**, nor an observed production installation.
- **Install/start/config:** that guide uses external `<YAJSW_HOME>/conf/wrapper.conf`, `<YAJSW_HOME>/bat/installService.bat`, `startService.bat`, `stopService.bat` and `runConsole.bat`. Its example sets `wrapper.java.app.mainclass=org.wso2.carbon.bootstrap.Bootstrap`, `wrapper.ntservice.name="WSO2CARBON"`, JAR classpaths, and product-specific plugin/dropins/patches/servicepacks paths. These batch files come from **YAJSW**, not product-ei's checked-in tree. The [pinned Carbon Kernel default config][kernel-wrapper] separately confirms Bootstrap (line 21), one service name (45–49), JAR classpaths (76–78), and plugins path (97). The kernel default layout differs from EI's guide; they are not interchangeable configurations.
- **Multiple-product corroboration:** [Carbon 4.4.1's official guide][carbon-multiple] explicitly describes an ESB + DSS **two-service** deployment, with two YAJSW directories and separate product homes/port offset. This is corroborating historical family documentation, **not a pinned EI 6.6.0 two-product deployment**. Neither it nor EI's minimal example establishes a service dependency DAG. The examples reuse a single default service name; unique names/configuration and port separation must be checked before any future multi-instance test. The old guide also alternates `bat`/`bin` paths; do not blindly execute it.
- **Actual batch paths:** [integrator.bat][ei-integrator] checks JDK/home (27–54), assembles JAR classpaths (69–73), sets scattered plugin/dropins/patch/lib locations (171), and invokes Bootstrap (176). [broker.bat][ei-broker] line 66 forwards to `wso2/broker/bin/wso2server.bat`; [business-process.bat][ei-bps] line 66 forwards to the corresponding business-process server. These are **launchers**, not `javac` builds. All 42 `.bat` blobs in the complete pinned tree were read; no direct `javac` compiler command appeared (`JAVACMD` variables are Java launcher variables, not compiler evidence).
- **Build/packaging:** [distribution/pom.xml][ei-dist] lines 184–188 consume a kernel ZIP; 328–343 unzip/modify/re-ZIP component JARs. Lines 255–258 fetch a **moving `update.zip`** during a Maven build: a pinned source checkout alone does not guarantee reproducible artifacts.
- **Plugin/classloader source:** [CarbonLauncher.java][kernel-launcher] lines 59–61 describe launching Equinox via a child-first classloader; 81–99 construct it and load EclipseStarter; 195–203 locate the framework under `plugins`. [DropinsBundleDeployer.java][kernel-dropins] lines 130–159 read `JarFile` manifests, bundle symbolic names/versions and fragment metadata. This is genuine modular plugin/bundle infrastructure, **not evidence of loose `.class` plugins**. Hot replacement of arbitrary user classes was not verified.

### Onboarding value / limits

Good challenge for per-service inventory, independent profile releases, duplicated homes, mutable configurations, port isolation, dependency provenance and rollback boundaries. The source layout is complex, but the build is Maven-based; do not describe it as an ad-hoc batch compiler. Actual SCM dependencies/start order and a fixed deployment's service count remain unverified.

**Prerequisites before a future isolated build:** compatible JDK and Maven/product dependencies; [official EI prerequisites][ei-prereqs] specify Ant 1.7+ for samples, 4 GB RAM and 10 GB disk for a single product baseline, with higher multi-instance resource examples. An exact tested JDK/wrapper pairing was not resolved here. The launcher itself checks 1.7/1.8/9/10/11 (138–147), but that is not proof every pairing works. The legacy wrapper example contains `MaxPermSize`; review JVM flags rather than assuming modern-JDK compatibility. EI documentation requests lower-case `java_home`/`carbon_home`; preserve its documented distinction when inspecting wrapper interpolation, without asserting Windows environment variables are case-sensitive. No historical dependency/download availability was tested.

## 2. eXist-db 3.6.1 — strongest vendored legacy YAJSW fixture

**Repository:** <https://github.com/eXist-db/exist>

**Pinned snapshot:** tag `eXist-3.6.1` resolves to `3be6286d3085626fc9a7fd711be12f424367298f` ([commit API][exist-pin], [tree API][exist-tree]).

### Evidence

- **Batch build:** [build.bat][exist-bat] lines 27–36 select vendored Ant 1.10.1 and endorsed libs; line 48 invokes `org.apache.tools.ant.launch.Launcher`. It does **not** directly call `javac`. All 23 pinned `.bat` files were inspected; no direct compiler invocation was found.
- **Real loose compiled adapter:** [build/scripts/build-impl.xml][exist-build] lines 523–525 include `wrapper` in the default `all` target; 798–801 invoke `tools/yajsw/build.xml`. [That wrapper build][exist-wrapper-build] defines `tools/yajsw/classes` (16–20) and compiles the application-specific Java source there using Ant `<javac>` (83–91), with no adapter JAR packaging target. [wrapper.conf.in][exist-conf] sets `org.exist.yajsw.Main` (50) and **that class directory** (89) ahead of `start.jar` (90). This verifies a real application `.java → loose .class → YAJSW classpath` path, **via Ant**, not a direct compiler command in `.bat`.
- **Application adapter source:** [tools/yajsw/src/org/exist/yajsw/Main.java][exist-adapter] lines 25–31 construct the bootstrap classpath/classloader and load `org.exist.jetty.JettyStart`; 55–60 notify YAJSW about shutdown/startup. This is consumer-specific code, not just an unrelated wrapper library checkout.
- **Windows installation/start:** [installService.bat][exist-install] lines 1–3 change to the script directory, call `setenv.bat`, then invoke wrapper `-i`; [startService.bat][exist-start] lines 1–3 invoke `-t`. [setenv.bat][exist-env] lines 12–24 wire wrapper JARs, `bin/wrapper.bat` and `conf/wrapper.conf`. The checked-in config is a **template**; [wrapper build][exist-wrapper-build] lines 38–57 generate the actual config from home/JVM/memory tokens.
- **Service count/dependencies:** [wrapper build][exist-wrapper-build] lines 44–46 assign the single default name `eXist-db`; [config][exist-conf] lines 182–194 use that name, leave `wrapper.ntservice.dependency.1` commented out and enable `AUTO_START`. **One service definition verified; zero active SCM dependency entries in this template.** Multiple separately named deployments remain unverified.
- **Dynamic plugin mechanism, without overclaiming packaging:** [PluginsManagerImpl.java][exist-plugins] lines 135–145 discover and construct `Plug` implementations; 199–212 support adding by class name; 223–244 discover `META-INF/services` and call `Class.forName(..., ldr)`. Its [EXistClassLoader][exist-loader] supports adding URLs at runtime (14–27). That confirms reflective/SPI plugins, **not a directory-of-loose-plugin-classes deployment or reliable live unload/reload**. The source itself includes temporary-for-testing registrations (93–96).
- **Distribution differs from the adapter:** [build-impl.xml][exist-build] packages normal application classes into `exist.jar`, `start.jar`, `exist-optional.jar` (387–454). [start.config][exist-start-config] lists `lib/extensions`, `lib/plugins`, `lib/user` and many per-extension library directories (84–112); `/*` explicitly means JAR/ZIP enumeration (16–18). Therefore do **not** claim loose external plugins based merely on `lib/plugins` or a URLClassLoader. `test/classes` (35) is a testing mode path, not deployed plugin evidence.
- **Dependency sprawl:** the [complete tree][exist-tree] includes `tools/yajsw/lib/core/{commons,jna,netty,yajsw}`, `lib/extended` Groovy/Velocity/YAJSW libraries, `wrapper.jar`/`wrapperApp.jar`, plus `bin`, installer batch scripts and per-extension libs. This is a concrete distribution layout rather than a subjective claim of poor engineering.

### Onboarding value / limits

Probably the best first **source-tree-based** onboarding challenge: preserve Ant build outputs, loose wrapper adapter, configuration token expansion, vendored wrapper dependencies, and persistent database/config/log boundaries. It fails the multi-service requirement and does not establish loose external plugins. Do not upgrade the scope to multiple services by making synthetic duplicate instances and then call that historical evidence.

**Prerequisites:** [BUILD.md][exist-build-doc] states Java 8 and supplied Ant; installer generation additionally needs IzPack. [build.properties][exist-properties] lines 21–22 target Java 1.8. Wrapper generation requires `EXIST_HOME`/`JAVA_HOME` ([wrapper build][exist-wrapper-build], 41–42). Its `prepare` target deletes/recreates wrapper log/work directories (69–73); this matters for release safety. Checked-in third-party JAR presence does not verify licenses, checksums, security, or current download availability.

## 3. ImageJ 1.51u — verified direct batch compiler and loose plugin loader

**Repository:** <https://github.com/imagej/ImageJ>

**Pinned snapshot:** tag `v1.51u` resolves to `e52a4b2c888ed0170384706b3aa87af1b2f4e5c8` ([commit API][ij-pin], [tree API][ij-tree]). This historical pin was inspected, not the search result's moving `master`.

### Evidence

- **Actual complete Windows build script:** [compile.bat][ij-bat] is exactly five lines:

  ```bat
  javac ij\ImageJ.java
  javac ij\plugin\*.java
  javac ij\plugin\filter\*.java
  javac ij\plugin\frame\*.java
  java ij.ImageJ
  ```

  There is no `jar` command or output `-d`: the compiler's default output is loose classes alongside source, and line 5 launches from the class tree. This script builds **built-in** plugin packages; it does not copy an external plugin into the `plugins` directory. It also immediately launches a GUI, so it is not a safe compile-only probe.
- **Loose external plugins, not inferred from JARs:** [Menus.java][ij-menus] lines 1022–1028 inspect actual filesystem `.class` names with underscores; 1058–1065 discover them in subdirectories. [PluginClassLoader.java][ij-loader] lines 6–16 document directory/subdirectory/JAR search; 45–46 add the plugin directory URL, and 65–79 add immediate subdirectories. JAR/ZIP support is a separate branch (83–91).
- **Loader is actually used:** [IJ.java][ij-ij] lines 2123–2144 create `PluginClassLoader` for the plugin path; 219–223 load/instantiate a class and invoke `PlugIn` or `PlugInFilter`; 2198–2199 reset the loader. This closes the discovery-to-loader-to-execution evidence chain.
- **Compile/run path for user plugins:** [ij/plugin/Compiler.java][ij-compiler] lines 48–70 accept `.class` directly or compile `.java`; 109–156 pass source/target/classpath options, with no JAR packaging or `-d`; 317–327 reset the loader, load the resulting class, and invoke the plugin. Lines 159–194 combine the current classpath, the source directory and plugin-folder JARs. This is genuine mixed loose-class/JAR plugin support, but its external-plugin compiler path is **Java compiler API/reflection, not the supplied batch script**.
- **Windows services:** complete pinned tree contains `compile.bat` and `run_appletviewer.bat`, no YAJSW service configuration/install/start scripts. YAJSW consumption, service count and SCM dependencies therefore remain **unverified**, not silently added by this report.

### Onboarding value / limits

Best real fixture for tracking source-adjacent generated classes, stale class deletion, plugin directory/subdirectory boundaries, mixed JAR/loose outputs and loader resets. The loader only scans one directory level (source doc lines 16 and 65–80), and menu discovery uses underscore naming conventions. Do not describe it as a background Windows service suite or as evidence of widely scattered batch scripts.

**Prerequisites:** Windows `cmd.exe`, JDK `javac` and `java` on PATH, working directory at the source root for this batch. A historical JDK 8 is a reasonable **untested starting point**, not a verified build result: the plugin compiler defaults to target 1.6 (18–25) and still exposes older targets, so current JDK support must be checked. Its compiler can download `Compiler.jar` when javac is unavailable (55–65); keep any future experiment network-isolated until that behavior is reviewed. Plugins execute code in-process and need the same trust review as the application.

## 4. YAJSW mirror and samples — reference only

**Repository:** <https://github.com/yajsw/yajsw> (its own description calls it a mirror).

**Pinned snapshot:** `a81c808dbd91df5cb5cbba219a3f2c234a113434`, resolved from `master` during inspection ([commit API][yajsw-pin], [tree API][yajsw-tree]). [readme.txt][yajsw-readme] labels the source `yajsw-stable-12.14`; this is **not verification that this commit equals a signed/released 12.14 archive**.

- [bat/installService.bat][yajsw-install] and [bat/startService.bat][yajsw-start], lines 1–4, invoke `-i` and `-t` through `setenv.bat`. [setenv.bat][yajsw-env] lines 12–14 reference wrapper JARs and their library tree; 31–32 select `conf/wrapper.conf`.
- [bat/runHelloWorld.bat][yajsw-hello] line 6 runs `test.HelloWorld` from `wrapper.jar`/`wrapperApp.jar`; it **does not compile loose classes**. All 25 batch files were read: no direct `javac` compiler command found.
- [conf/samples/wrapper.equinox.conf][yajsw-equinox] lines 3–9 use `org.eclipse.osgi_3.1.2.jar` and one service named `equinox osgi`. This is an externally supplied OSGi framework sample, **not a verified consumer application or loose-class plugin fixture**.
- First-party [migration documentation][yajsw-migration], “One wrapper multiple applications,” explains monitoring multiple applications / invoking the wrapper with multiple configurations. That capability is **not proof of multiple separately registered SCM services in any candidate**. [Configuration documentation][yajsw-parameters] documents service dependency configuration; the [pinned default config][yajsw-default] names one service `yajsw` (170) and leaves `wrapper.ntservice.dependency.1` commented (179). That is not a real application dependency graph.
- [build/gradle/build.gradle][yajsw-build] lines 46–59 use local disk `flatDir` dependencies and lines 67–68 target Java 1.7. [readme][yajsw-readme] line 5 says Gradle 5.4.1, Java 8 for Gradle and Java 7 for compilation. No wrapper build was attempted.

## Reproduction, scope and safety

**Access without giant clones:** use each linked commit tree / raw file, or GitHub's snapshot archive route `https://github.com/<owner>/<repo>/archive/<full-sha>.zip` after checking size. Tag-to-SHA resolution and file retrieval were verified; archive download availability/size and released binary checksums were **not** tested. The complete recursive tree responses were not truncated. Inspection used bounded GitHub API/raw-source reads and official documentation, with every batch file in EI/eXist/YAJSW read to distinguish compiler commands from launcher variables.

**Search scope:** searches covered YAJSW, “Yet Another Java Service Wrapper,” Java plugin/classloader, multi-service Windows deployment, `build.bat`/`javac`, historical WSO2/Carbon and ImageJ, and OpenRemote/JPF leads. Only first-party repositories/docs are used as evidence above. OpenRemote was not promoted: no inspected primary source established this intersection. Search provider rate limiting (and an unavailable alternative API key) limited further discovery; **“not verified” does not mean no such public project exists**. Modern tags and old family documentation were not blended into a fictional deployment.

**Before any later build/install:** use a disposable Windows VM, inspect build hooks and downloaded artifact provenance, inventory service identities/ports/accounts/start order, isolate network access and persistent data, and separate build-only commands from launch/install commands. Do not run these old scripts on the research host, production SCM or a live database directory. Review JVM flags, outdated vendored libraries and legacy URLs. EI's moving update download and example credentials/hostname-verification settings, eXist's destructive wrapper preparation, and ImageJ's auto-launch/download behavior are concrete reasons to keep the first phase read-only. A historical tag is evidence of source, not a security or reproducibility guarantee.

**Recommendation:** choose **eXist 3.6.1 first** if the goal is a bounded, realistic source-tree onboarding exercise; choose **EI 6.6.0** when documented multiple YAJSW Windows services are non-negotiable; add **ImageJ 1.51u as a separate real loose-plugin exercise**. No candidate should be marketed as satisfying all requirements.

[ei-pin]: https://api.github.com/repos/wso2/product-ei/commits/v6.6.0
[ei-tree]: https://api.github.com/repos/wso2/product-ei/git/trees/bfdf341ab6dcfccce35c88b8a1567604f07ba8f5?recursive=1
[ei-pom]: https://github.com/wso2/product-ei/blob/bfdf341ab6dcfccce35c88b8a1567604f07ba8f5/pom.xml#L1696
[ei-windows]: https://wso2docs.atlassian.net/wiki/spaces/EI660/pages/6522341/Running+the+Product+as+a+Windows+Service
[ei-prereqs]: https://wso2docs.atlassian.net/wiki/spaces/EI660/pages/6520951/Installation+Prerequisites
[carbon-multiple]: https://wso2docs.atlassian.net/wiki/spaces/Carbon441/pages/13041718
[ei-integrator]: https://github.com/wso2/product-ei/blob/bfdf341ab6dcfccce35c88b8a1567604f07ba8f5/distribution/src/scripts/integrator.bat
[ei-broker]: https://github.com/wso2/product-ei/blob/bfdf341ab6dcfccce35c88b8a1567604f07ba8f5/distribution/src/scripts/broker.bat#L66
[ei-bps]: https://github.com/wso2/product-ei/blob/bfdf341ab6dcfccce35c88b8a1567604f07ba8f5/distribution/src/scripts/business-process.bat#L66
[ei-dist]: https://github.com/wso2/product-ei/blob/bfdf341ab6dcfccce35c88b8a1567604f07ba8f5/distribution/pom.xml
[kernel-pin]: https://api.github.com/repos/wso2/carbon-kernel/commits/v4.5.3
[kernel-wrapper]: https://github.com/wso2/carbon-kernel/blob/e07e00f16b91983e679d04f80aeba67fb08ebe39/distribution/kernel/carbon-home/bin/yajsw/wrapper.conf
[kernel-launcher]: https://github.com/wso2/carbon-kernel/blob/e07e00f16b91983e679d04f80aeba67fb08ebe39/core/org.wso2.carbon.server/src/main/java/org/wso2/carbon/server/CarbonLauncher.java
[kernel-dropins]: https://github.com/wso2/carbon-kernel/blob/e07e00f16b91983e679d04f80aeba67fb08ebe39/core/org.wso2.carbon.server/src/main/java/org/wso2/carbon/server/extensions/DropinsBundleDeployer.java
[exist-pin]: https://api.github.com/repos/eXist-db/exist/commits/eXist-3.6.1
[exist-tree]: https://api.github.com/repos/eXist-db/exist/git/trees/3be6286d3085626fc9a7fd711be12f424367298f?recursive=1
[exist-bat]: https://github.com/eXist-db/exist/blob/3be6286d3085626fc9a7fd711be12f424367298f/build.bat
[exist-build]: https://github.com/eXist-db/exist/blob/3be6286d3085626fc9a7fd711be12f424367298f/build/scripts/build-impl.xml
[exist-wrapper-build]: https://github.com/eXist-db/exist/blob/3be6286d3085626fc9a7fd711be12f424367298f/tools/yajsw/build.xml
[exist-conf]: https://github.com/eXist-db/exist/blob/3be6286d3085626fc9a7fd711be12f424367298f/tools/yajsw/conf/wrapper.conf.in
[exist-adapter]: https://github.com/eXist-db/exist/blob/3be6286d3085626fc9a7fd711be12f424367298f/tools/yajsw/src/org/exist/yajsw/Main.java
[exist-install]: https://github.com/eXist-db/exist/blob/3be6286d3085626fc9a7fd711be12f424367298f/tools/yajsw/bin/installService.bat
[exist-start]: https://github.com/eXist-db/exist/blob/3be6286d3085626fc9a7fd711be12f424367298f/tools/yajsw/bin/startService.bat
[exist-env]: https://github.com/eXist-db/exist/blob/3be6286d3085626fc9a7fd711be12f424367298f/tools/yajsw/bin/setenv.bat
[exist-plugins]: https://github.com/eXist-db/exist/blob/3be6286d3085626fc9a7fd711be12f424367298f/src/org/exist/plugin/PluginsManagerImpl.java
[exist-loader]: https://github.com/eXist-db/exist/blob/3be6286d3085626fc9a7fd711be12f424367298f/src/org/exist/start/EXistClassLoader.java
[exist-start-config]: https://github.com/eXist-db/exist/blob/3be6286d3085626fc9a7fd711be12f424367298f/src/org/exist/start/start.config
[exist-build-doc]: https://github.com/eXist-db/exist/blob/3be6286d3085626fc9a7fd711be12f424367298f/BUILD.md
[exist-properties]: https://github.com/eXist-db/exist/blob/3be6286d3085626fc9a7fd711be12f424367298f/build.properties#L21-L22
[ij-pin]: https://api.github.com/repos/imagej/ImageJ/commits/v1.51u
[ij-tree]: https://api.github.com/repos/imagej/ImageJ/git/trees/e52a4b2c888ed0170384706b3aa87af1b2f4e5c8?recursive=1
[ij-bat]: https://github.com/imagej/ImageJ/blob/e52a4b2c888ed0170384706b3aa87af1b2f4e5c8/compile.bat
[ij-menus]: https://github.com/imagej/ImageJ/blob/e52a4b2c888ed0170384706b3aa87af1b2f4e5c8/ij/Menus.java
[ij-loader]: https://github.com/imagej/ImageJ/blob/e52a4b2c888ed0170384706b3aa87af1b2f4e5c8/ij/io/PluginClassLoader.java
[ij-ij]: https://github.com/imagej/ImageJ/blob/e52a4b2c888ed0170384706b3aa87af1b2f4e5c8/ij/IJ.java
[ij-compiler]: https://github.com/imagej/ImageJ/blob/e52a4b2c888ed0170384706b3aa87af1b2f4e5c8/ij/plugin/Compiler.java
[yajsw-pin]: https://api.github.com/repos/yajsw/yajsw/commits/a81c808dbd91df5cb5cbba219a3f2c234a113434
[yajsw-tree]: https://api.github.com/repos/yajsw/yajsw/git/trees/a81c808dbd91df5cb5cbba219a3f2c234a113434?recursive=1
[yajsw-readme]: https://github.com/yajsw/yajsw/blob/a81c808dbd91df5cb5cbba219a3f2c234a113434/readme.txt
[yajsw-install]: https://github.com/yajsw/yajsw/blob/a81c808dbd91df5cb5cbba219a3f2c234a113434/bat/installService.bat
[yajsw-start]: https://github.com/yajsw/yajsw/blob/a81c808dbd91df5cb5cbba219a3f2c234a113434/bat/startService.bat
[yajsw-env]: https://github.com/yajsw/yajsw/blob/a81c808dbd91df5cb5cbba219a3f2c234a113434/bat/setenv.bat
[yajsw-hello]: https://github.com/yajsw/yajsw/blob/a81c808dbd91df5cb5cbba219a3f2c234a113434/bat/runHelloWorld.bat
[yajsw-equinox]: https://github.com/yajsw/yajsw/blob/a81c808dbd91df5cb5cbba219a3f2c234a113434/conf/samples/wrapper.equinox.conf
[yajsw-default]: https://github.com/yajsw/yajsw/blob/a81c808dbd91df5cb5cbba219a3f2c234a113434/conf/wrapper.conf.default#L170-L179
[yajsw-build]: https://github.com/yajsw/yajsw/blob/a81c808dbd91df5cb5cbba219a3f2c234a113434/build/gradle/build.gradle
[yajsw-migration]: https://yajsw.sourceforge.io/Migrating%20from%20JSW.html
[yajsw-parameters]: https://yajsw.sourceforge.io/YAJSW%20Configuration%20Parameters.html
