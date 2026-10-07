# eXist-db 3.6.1 onboarding assessment

## Decision and evidence boundary

**Real source candidate; build and deployment are blocked, not successful.** Snapshot: `3be6286d3085626fc9a7fd711be12f424367298f` (eXist-3.6.1). This assessment inspected pinned upstream text over HTTPS; it did not download/integrate a source checkout, run upstream scripts/classes, install dependencies, launch Java, or operate Windows services. Source acquisition and onboarding artifacts belong to the parent task. No stub eXist classes may stand in for these outputs.

Current environment information supplied by the task: JDK 25 only; no known Java 8 or independently installed Ant. This is not a new machine inventory. Upstream documents Java 8 and **bundled Ant**, so absence of system Ant is not itself a blocker once the pinned source and bundled dependencies are verified. [BUILD][build-doc] [BAT][bat]

### Concrete blockers

| Gate | Blocker / required decision |
|---|---|
| Historic compilation | Approved Java 8 JDK unavailable. BAT supplies `-Djava.endorsed.dirs`, an obsolete modern-JVM mechanism; source/target 1.8 alone does not make the launcher, native2ascii task, AspectJ 1.9.0.RC1 or old wrapper compatible with JDK 25. Do not change flags and call that the preserved historic build. [BAT][bat] [properties][props] [implementation][impl] |
| Inputs/provenance | Bundled Ant 1.10.1 launcher, its task libraries, AspectJ, wrapper jars/native payloads and application dependencies must be present and hashed. Exact resolved `%latest%` runtime filenames remain an inventory gate, not an assumption. [BAT][bat] [implementation][impl] [runtime inventory][start-config] |
| Default build network | `all` includes `extensions-xar` when enabled; properties enable it and configure an HTTP package repository. Setup fetches missing XARs. Pin the real packages/provenance or explicitly disable this optional feature in a reviewed exercise build; neither choice is equivalent to proving a complete historical default distribution. [implementation][impl] [properties][props] [setup][setup] |
| Execution permission | No upstream execution approved yet. Inspect recursively imported Ant files and extension targets before any build. No dependency/JDK installation permission; no service installation/start/stop/uninstall permission. |
| Real deployment capability | `src/ReleaseFlow.psm1`, `Read-RfConfig`, currently accepts **only `Simulated` services and health checks** and refuses real modes. Real SCM control, application readiness and quiescence are not implemented. A simulated run can test file mechanics only; it cannot prove eXist startup/stop or deployment safety. |
| Operational ownership | Actual service registration/name/account, paths, JVMs, ports, health/authentication, backup/restore and schema/data rollback policy are unknown. Database data rollback is not binary rollback. Requires operator-approved disposable VM first, not access to an existing database. |

## Authoritative workflow and outputs

`build.bat` selects `%EXIST_HOME%` (defaults to current directory), `%JAVA_HOME%\bin\java` or PATH Java, sets `ANT_HOME=...\tools\ant`, and invokes `org.apache.tools.ant.launch.Launcher`, passing only the first nine arguments. It is **BAT → bundled Ant → compiler/tasks**, not direct BAT `javac`. Ambient `CLASSPATH` and `JAVA_OPTS` enter the invocation and must be recorded/controlled. [BAT][bat]

Root `build.xml` loads `local.build.properties` before defaults and imports implementation, signing, installer, distribution, minimal, JUnit and performance scripts. `all` includes `prepare,jar,wrapper,extension-betterform,extension-modules,extension-xprocxq,extensions-xar,test-compile`; its body calls extension builds, Active Directory after LDAP, and conditional signing. This is more than compiling the adapter. [root build][root] [implementation][impl]

| Output | Owner/evidence | Deployment meaning |
|---|---|---|
| `build/classes/org/**` | Main Ant `compile`; permission aspect separately woven by `compile-aspectj` | Intermediate, not a substitute production payload |
| `exist.jar` | `jar` target, core classes/resources with explicit exclusions | Required core payload |
| `start.jar` | Same target, `org/exist/start/**`; manifest `Main-Class=org.exist.start.Main`; embeds `start.config` | Bootstrap and runtime classpath policy |
| `exist-optional.jar` | Same target includes HTTP, Jetty, SOAP, Ant and other excluded optional packages | Required Jetty adapter target classes; not optional for this selected service route |
| `exist-testkit.jar` and `test/classes` | `jar` / `compile-testkit`; default build also test-compiles | Build/test output, exclude from initial production scope |
| `tools/yajsw/classes/org/exist/yajsw/Main.class` | Wrapper Ant `compile` to `classes`, no adapter JAR target | **Genuine loose application-specific adapter**, required by wrapper classpath |
| `tools/yajsw/conf/wrapper.conf`, `wrapper.conf.install`, `conf/log4j2.xml` | Wrapper token filtering / XSLT | Generated deployment configuration, requires target-specific review; do not ship build-machine paths blindly |
| Extension artifacts / XAR packages | `all` delegates extension build files and setup | Exact artifact list unresolved until imported files and resulting inventory are reviewed; not covered by the three main jars alone |

Sources: [implementation][impl] [wrapper build][wrapper-build]. Installer additionally needs IzPack; it is not required merely to compile. `dist-zip` / `dist-war` are documented packaging routes, not commands executed or verified here. [BUILD][build-doc]

### Classpath and dependency closure

* **Wrapper build:** `wrapperApp.jar` relative to wrapper build base directory, root `start.jar`, root `exist.jar`. Compile the real `Main.java` against these, preserving its upstream sources. [wrapper build][wrapper-build]
* **Main build:** all JARs in `lib/core`, `lib/optional`, `lib/endorsed`, `lib/user`, `lib/extensions`, extension `**/lib/*.jar`, `tools/ant/lib`; `tools/yajsw/wrapper.jar` and wrapper commons-configuration; Jetty and AspectJ paths are added for compilation. There is also ambient Java classpath in `classpath.core`. [implementation][impl]
* **Wrapper controller process:** scripts use PATH `java` independently of application `wrapper.java.command`. `wrapper.jar` loads its required `tools/yajsw/lib/...` dependencies. Preserve `wrapper.jar`, `wrapperApp.jar`, **entire verified wrapper dependency closure**, and scripts, not just adapter classes. `setenv.bat` supplies a 30 MB heap and wrapper temp/JNA option. [setenv][env] [wrapper BAT][wrapper-bat]
* **Application initial classpath:** adapter class directory and relative `start.jar`; working directory `../..` is intended to be the product root. Native library path is `lib`. [template][conf]
* **Application bootstrap:** adapter constructs `org.exist.start.Main("jetty")`, detects home, constructs classpath, sets context classloader, and reflectively calls `JettyStart.run(String[], Observer)`. `start.config` requires `exist.jar`, `exist-optional.jar`, endorsed jars, explicitly named core families (ANTLR, crypto, Commons, Jackson, JTA, logging, XMLDB/XMLRPC, Quartz, ICU, Caffeine, j8fu etc.), optional jars for Jetty, and scattered extension libs. [adapter][adapter] [bootstrap][bootstrap] [runtime inventory][start-config]
* Jetty mode includes `lib/extensions/*`, `lib/plugins/*`, `lib/user/*`, `lib/*`, BetterFORM/contentextraction/debuggee/EXPath/EXQuery/RESTXQ/Lucene/spatial/modules/replication/OpenID/OAuth/WebDAV/XProc/XQDoc libs, `tools/ant/lib/ant-%latest%.jar`, XMLUnit core/legacy/matchers, Jetty, IRC bot and AspectJ libraries. `/*` enumerates **JAR/ZIP**, not loose plugin classes. `test/classes` is only `mode == other`, not this service. Freeze resolved dependency names and hashes; preserve mode conditions rather than flattening every directory into one classpath. [runtime inventory][start-config]

Protecting `lib/user`/`lib/plugins` below is an ownership decision, not permission to omit them from dependency/readiness validation. Their contents can affect runtime even when not deployed by Release Flow.

## Destructive and mutable behavior

* Wrapper `compile` always depends on `prepare`: deletes/recreates **`tools/yajsw/logs` and `work`**, then writes transformed wrapper logging config. Never compile in a live installation. Wrapper `clean` removes classes and both generated wrapper configs. `create-conf` only runs if `wrapper.conf` was absent when Ant loaded the build; an existing config can therefore remain stale after home/JDK changes. Generation needs `EXIST_HOME`/`JAVA_HOME`; installer-oriented tokens are not a verified local runtime config. [wrapper build][wrapper-build]
* Main `prepare` creates Jetty logs/work and copies templates into root configs and webapp files (web.xml explicitly overwritten), installer config and a source resource. Treat every generated config as mutable, not a safe no-op on an installation. ANTLR target deletes generated parser `.java`/`.txt` files before regeneration. [implementation][impl]
* `clean` removes classes/JARs, distribution, logs/temp, test outputs, wrapper config/classes and extension artifacts, including a fallback deletion of `lib/extensions/*.jar`. `clean-conf` deletes `conf.xml`. **`clean-default-data-dir` deletes journals, DB/index files and package repositories; `clean-all` depends on it**, and also deletes configs, autodeploy and more. `rebuild` is `clean,all`. Ban these against production and retained baselines. [implementation][impl]
* Startup is not read-only: Jetty loads DB configuration and calls `BrokerPool.configure`; it starts webserver components and installs shutdown hooks. Persistence/recovery, logging, temp files and application deployments require disposable data and inspected startup triggers/configuration. The inspected bootstrap's “clean up tempdir” comment only normalizes/sets a path: **no deletion was found in that bootstrap**, so do not invent a launcher-wide recursive deletion. [Jetty][jetty] [bootstrap][bootstrap]
* Wrapper log policy explicitly rolls at 10 MB and retains 10 files; old logs can be deleted through normal operation. `wrapper.on_exit.0=SHUTDOWN`, default nonzero exit `RESTART`: unexpected termination is not automatically a quiescent deployment window. [template][conf]

## Exact supported topology and lifecycle evidence

**One generated SCM service:** `eXist-db`, display `eXist-db Native XML Database`, automatic startup. The dependency entry is commented out: **no active SCM dependency graph**, not multiple services. Service/app accounts are unset/commented in template; actual account must be inventoried, not guessed. [wrapper build][wrapper-build] [template][conf]

```text
installService.bat → setenv.bat → wrapper.bat → java -jar wrapper.jar -i wrapper.conf
startService.bat   → setenv.bat → wrapper.bat → java -jar wrapper.jar -t wrapper.conf
stopService.bat    → setenv.bat → wrapper.bat → java -jar wrapper.jar -p wrapper.conf
SCM service / YAJSW controller → wrapped application JVM
    → org.exist.yajsw.Main → bootstrap classloader → JettyStart + BrokerPool
```

The batch scripts first `cd %~dp0` (unquoted and without `/d`); path-with-spaces and cross-drive behavior must be checked in the future VM, not silently rewritten as a different historical workflow. Controller JVM uses PATH Java while generated app JVM points at `JAVA_HOME/bin/java`. [install][install] [start][start] [stop][stop] [setenv][env] [wrapper BAT][wrapper-bat]

Adapter observes literal `started` / `shutdown` and calls YAJSW `reportServiceStartup()` / `signalStopping(10000)`. Jetty passes the observer into `BrokerPool.configure`; BrokerPool reports `SIGNAL_STARTED` / `SIGNAL_SHUTDOWN`, whose constants are those literals. **These are database lifecycle notifications, not proof that every HTTP context is healthy.** Jetty's separate signal is `jetty started`; the adapter does not match it. [adapter][adapter] [Jetty][jetty] [BrokerPool][pool] [constants][constants]

Jetty registers DB shutdown listener and JVM shutdown hook. The listener schedules server stop/join after 1 second when no DB instances remain. The hook calls `BrokerPool.stopAll(true)` then stops Jetty unless already stopping/stopped. Explicit `JettyStart.shutdown()` removes that hook, calls `stopAll(false)`, then waits for stopped status. This is source-level clean-shutdown intent, **not verified delivery of YAJSW `-p` into this hook, measured shutdown latency, successful database flush, or an installed service observation**. Wrapper binaries/native behavior needs approved runtime validation. [Jetty][jetty]

## Candidate deployment scope — non-executable draft

This is an operator/design proposal, **not a runnable configuration for the current core**. `WindowsScm` and `ExistReadiness` below are deliberately unsupported future contracts. Do not change them to `Simulated` and present the result as production onboarding. Paths/name are prospective VM choices, not observed installed values.

```json
{
  "SchemaVersion": 1,
  "TargetId": "exist-361-lab",
  "ProductionPath": "C:/exist-361-lab/product",
  "StatePath": "C:/exist-361-lab/release-state",
  "ManagedPaths": [
    "exist.jar", "exist-optional.jar", "start.jar", "bin",
    "lib/core", "lib/optional", "lib/endorsed", "lib/extensions",
    "extensions", "tools/ant/lib", "tools/aspectj/lib", "tools/ircbot/lib",
    "tools/jetty/lib", "tools/yajsw/classes", "tools/yajsw/bin",
    "tools/yajsw/lib", "tools/yajsw/wrapper.jar", "tools/yajsw/wrapperApp.jar",
    "webapp"
  ],
  "ProtectedPaths": [
    "conf.xml", "client.properties", "descriptor.xml", "mime-types.xml", "log4j2.xml",
    "lib/user", "lib/plugins", "autodeploy",
    "tools/yajsw/conf", "tools/yajsw/logs", "tools/yajsw/work", "tools/yajsw/tmp",
    "tools/jetty/etc", "tools/jetty/logs", "tools/jetty/work", "tools/jetty/tmp",
    "webapp/WEB-INF/data", "webapp/WEB-INF/expathrepo",
    "webapp/WEB-INF/logs", "webapp/WEB-INF/web.xml", "log", "tmp",
    ".exist_history", ".exist_query_history"
  ],
  "ServiceMode": "WindowsScm",
  "Services": [{ "Name": "eXist-db" }],
  "StopOrder": ["eXist-db"],
  "StartOrder": ["eXist-db"],
  "HealthCheck": { "Mode": "ExistReadiness", "Definition": "operator approval required" }
}
```

Before adoption, narrow broad `extensions`/`webapp` scopes to reviewed runtime files, enumerate loose root `lib/*.jar` referenced by bootstrap, and inspect all additional local state/extension config. This draft intentionally does **not** claim a closed payload inventory. Default data AND journal are `webapp/WEB-INF/data`; any operator override/external paths must be separately protected/backed up. EXPath repositories hold installed application state. Do not package DB/repository directories merely because they are under webapp. [properties][props] [implementation][impl]

Generated wrapper config and Jetty etc remain protected: provision approved absolute home/JVM, enabled Jetty configs, memory, ports and accounts out-of-band before first registration. The wrapper template warns to uninstall/reinstall before changing properties after service installation. Binary release must fail if protected configuration is incompatible; silently preserving old configuration is not sufficient. JDK installation/native registration and Release Flow state remain outside managed payload. [template][conf]

## Preserved BAT/Ant plan after explicit approval

1. Parent supplies pinned clean source and integrity manifest. Inspect imported build/extension tasks, package downloads, startup triggers and runtime configuration; freeze dependency closure and optional-feature choice. Record ambient environment and source SHA.
2. Provision an approved isolated Java 8 build VM/JDK; verify bundled Ant/task artifacts rather than installing a replacement build system. Set `JAVA_HOME`, `EXIST_HOME` to this **disposable source root**, isolated from target/data. Preserve upstream BAT/Ant and real adapter source.
3. Only after execution approval, use `cmd.exe` in the source root and the preserved `build.bat` workflow. A staged diagnostic `build.bat prepare jar wrapper` is a **partial build**, not `all`; a later reviewed `build.bat all` remains necessary for default extension/test compilation coverage. Do not assume disabling XAR retrieval proves default distribution completion. Inspect signing key presence before allowing conditional sign.
4. Capture task log, exact arguments, JDK, resolved dependency hashes, generated outputs and actual nonempty class files/JAR entries. Validate `Main.class`, bootstrap classes, `JettyStart`, woven core and extension outputs from the real build. Do not manufacture outputs or infer build success solely from file existence.
5. Stage only inventoried runtime files outside the source tree. Exclude test/source intermediates and generated machine-specific config; preserve directory layout. Never run Ant on the deployment root. A real application smoke test and separately authorized SCM test on disposable data are later gates.
6. For an approved real deployment, verify stop completion, process exit/file handles and data quiescence before replacement; start the single service then perform bounded SCM + authenticated DB/HTTP readiness checks on approved ports. Decide rollback policy for data changes/migrations before deploying. Current Release Flow cannot perform this phase.

## Safe validation available now (no legacy execution)

The following are **proposed checks**, not tests reported as passed by this note:

* After parent acquisition, read/hash the six principal upstream files and related imports against the pin; inventory BATs, jars, configs and source paths without invoking any upstream task/class. Reject missing adapter source, wrapper jars or Ant launcher.
* Parse Ant XML as data with DTD/external entity resolution disabled; enumerate imports, target dependencies and `delete`, `copy`, `exec`, `java`, `get`/fetch tasks recursively. No `ant -projecthelp`: loading taskdefs/build scripts is not a pure text read.
* Parse `start.config`/wrapper template as text; resolve token names, modes, JAR/ZIP wildcard matches and `%latest%` choices against source inventory. Check bootstrap/adapter package names and referenced config files. Inspect manifests/ZIP central directories with a trusted archive reader, never `java -jar`; read class-file headers/entry names if genuine outputs later exist.
* Verify managed/protected scope separation, containment, cross-drive paths and proposed state-root isolation by path calculations only. Report payload paths lacking explicit ownership; require zero protected files in prospective package manifests. Do not copy into a live installation.
* Inspect target configuration JSON/schema as data and demonstrate that a real-mode draft must be rejected by current core. Do not run Deploy/Recover or service actions to validate this note. Any separate synthetic Release Flow file-mechanics test must be labeled as such, not eXist validation.
* Safe inspection success means **source, inputs and scope reviewed**. Compilation, JVM compatibility, database/HTTP readiness, SCM behavior, upgrade and rollback remain **not executed / blocked**.

## Pinned primary sources

All upstream links below refer to the same immutable snapshot; relevant target/method/property names above provide precise search anchors.

[bat]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/build.bat
[impl]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/build/scripts/build-impl.xml
[wrapper-build]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/tools/yajsw/build.xml
[conf]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/tools/yajsw/conf/wrapper.conf.in
[start-config]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/src/org/exist/start/start.config
[adapter]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/tools/yajsw/src/org/exist/yajsw/Main.java
[build-doc]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/BUILD.md
[props]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/build.properties
[root]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/build.xml
[setup]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/build/scripts/setup.xml
[env]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/tools/yajsw/bin/setenv.bat
[wrapper-bat]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/tools/yajsw/bin/wrapper.bat
[install]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/tools/yajsw/bin/installService.bat
[start]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/tools/yajsw/bin/startService.bat
[stop]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/tools/yajsw/bin/stopService.bat
[bootstrap]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/src/org/exist/start/Main.java
[jetty]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/src/org/exist/jetty/JettyStart.java
[pool]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/src/org/exist/storage/BrokerPool.java
[constants]: https://raw.githubusercontent.com/eXist-db/exist/3be6286d3085626fc9a7fd711be12f424367298f/src/org/exist/storage/BrokerPoolConstants.java
