module dlangide.workspace.project;

import dlangide.workspace.workspace;
import dlangide.workspace.projectsettings;
import dlangui.core.logger;
import dlangui.core.collections;
import dlangui.core.settings;
import std.algorithm;
import std.array : empty;
import std.file;
import std.path;
import std.process;
import std.utf;

/// return true if filename matches rules for workspace file names
bool isProjectFile(in string filename) pure nothrow {
    return filename.baseName.equal("dub.json") || filename.baseName.equal("package.json");
}

string toForwardSlashSeparator(in string filename) pure nothrow {
    char[] res;
    foreach(ch; filename) {
        if (ch == '\\')
            res ~= '/';
        else
            res ~= ch;
    }
    return cast(string)res;
}

/// project item
class ProjectItem {
    protected Project _project;
    protected ProjectItem _parent;
    protected string _filename;
    protected dstring _name;

    this(string filename) {
        _filename = buildNormalizedPath(filename);
        _name = toUTF32(baseName(_filename));
    }

    this() {
    }

    @property ProjectItem parent() { return _parent; }

    @property Project project() { return _project; }

    @property void project(Project p) { _project = p; }

    @property string filename() { return _filename; }

    @property dstring name() { return _name; }

    @property string name8() {
        return _name.toUTF8;
    }

    /// returns true if item is folder
    @property const bool isFolder() { return false; }
    /// returns child object count
    @property int childCount() { return 0; }
    /// returns child item by index
    ProjectItem child(int index) { return null; }

    void refresh() {
    }

    ProjectSourceFile findSourceFile(string projectFileName, string fullFileName) {
        if (fullFileName.equal(_filename))
            return cast(ProjectSourceFile)this;
        if (project && projectFileName.equal(project.absoluteToRelativePath(_filename)))
            return cast(ProjectSourceFile)this;
        return null;
    }

    @property bool isDSourceFile() {
        if (isFolder)
            return false;
        return filename.endsWith(".d") || filename.endsWith(".dd") || filename.endsWith(".dd")  || filename.endsWith(".di") || filename.endsWith(".dh") || filename.endsWith(".ddoc");
    }

    @property bool isJsonFile() {
        if (isFolder)
            return false;
        return filename.endsWith(".json") || filename.endsWith(".JSON");
    }

    @property bool isDMLFile() {
        if (isFolder)
            return false;
        return filename.endsWith(".dml") || filename.endsWith(".DML");
    }

    @property bool isXMLFile() {
        if (isFolder)
            return false;
        return filename.endsWith(".xml") || filename.endsWith(".XML");
    }
}

/// Project folder
class ProjectFolder : ProjectItem {
    protected ObjectList!ProjectItem _children;

    this(string filename) {
        super(filename);
    }

    @property override const bool isFolder() {
        return true;
    }
    @property override int childCount() {
        return _children.count;
    }
    /// returns child item by index
    override ProjectItem child(int index) {
        return _children[index];
    }
    void addChild(ProjectItem item) {
        _children.add(item);
        item._parent = this;
        item._project = _project;
    }
    ProjectItem childByPathName(string path) {
        for (int i = 0; i < _children.count; i++) {
            if (_children[i].filename.equal(path))
                return _children[i];
        }
        return null;
    }
    ProjectItem childByName(dstring s) {
        for (int i = 0; i < _children.count; i++) {
            if (_children[i].name.equal(s))
                return _children[i];
        }
        return null;
    }

    override ProjectSourceFile findSourceFile(string projectFileName, string fullFileName) {
        for (int i = 0; i < _children.count; i++) {
            if (ProjectSourceFile res = _children[i].findSourceFile(projectFileName, fullFileName))
                return res;
        }
        return null;
    }

    bool loadDir(string path) {
        string src = relativeToAbsolutePath(path);
        if (exists(src) && isDir(src)) {
            ProjectFolder existing = cast(ProjectFolder)childByPathName(src);
            if (existing) {
                if (existing.isFolder)
                    existing.loadItems();
                return true;
            }
            auto dir = new ProjectFolder(src);
            addChild(dir);
            Log.d("    added project folder ", src);
            dir.loadItems();
            return true;
        }
        return false;
    }

    bool loadFile(string path) {
        string src = relativeToAbsolutePath(path);
        if (exists(src) && isFile(src)) {
            ProjectItem existing = childByPathName(src);
            if (existing)
                return true;
            auto f = new ProjectSourceFile(src);
            addChild(f);
            Log.d("    added project file ", src);
            return true;
        }
        return false;
    }

    void loadItems() {
        bool[string] loaded;
        string path = _filename;
        if (exists(path) && isFile(path))
            path = dirName(path);
        foreach(e; dirEntries(path, SpanMode.shallow)) {
            string fn = baseName(e.name);
            if (e.isDir) {
                loadDir(fn);
                loaded[fn] = true;
            } else if (e.isFile) {
                loadFile(fn);
                loaded[fn] = true;
            }
        }
        // removing non-reloaded items
        for (int i = _children.count - 1; i >= 0; i--) {
            if (!(toUTF8(_children[i].name) in loaded)) {
                _children.remove(i);
            }
        }
    }

    string relativeToAbsolutePath(string path) {
        if (isAbsolute(path))
            return path;
        string fn = _filename;
        if (exists(fn) && isFile(fn))
            fn = dirName(fn);
        return buildNormalizedPath(fn, path);
    }

    override void refresh() {
        loadItems();
    }
}

/// Project source file
class ProjectSourceFile : ProjectItem {
    this(string filename) {
        super(filename);
    }
    /// file path relative to project directory
    @property string projectFilePath() {
        return project.absoluteToRelativePath(filename);
    }
}

class WorkspaceItem {
    protected string _filename;
    protected string _dir;
    protected dstring _name;
    protected dstring _description;

    this(string fname = null) {
        filename = fname;
    }

    /// file name of workspace item
    @property string filename() { return _filename; }

    /// workspace item directory
    @property string dir() { return _dir; }

    /// file name of workspace item
    @property void filename(string fname) {
        if (fname.length > 0) {
            _filename = buildNormalizedPath(fname);
            _dir = dirName(filename);
        } else {
            _filename = null;
            _dir = null;
        }
    }

    /// name
    @property dstring name() { return _name; }

    @property string name8() {
        return _name.toUTF8;
    }

    /// name
    @property void name(dstring s) {  _name = s; }

    /// description
    @property dstring description() { return _description; }
    /// description
    @property void description(dstring s) { _description = s; }

    /// load
    bool load(string fname) {
        // override it
        return false;
    }

    bool save(string fname = null) {
        return false;
    }
}

/// detect DMD source paths
string[] dmdSourcePaths() {
    string[] res;
    version(Windows) {
        import dlangui.core.files;
        string dmdPath = findExecutablePath("dmd");
        if (dmdPath) {
            string dmdDir = buildNormalizedPath(dirName(dmdPath), "..", "..", "src");
            res ~= absolutePath(buildNormalizedPath(dmdDir, "druntime", "import"));
            res ~= absolutePath(buildNormalizedPath(dmdDir, "phobos"));
        }
    } else {
        res ~= "/usr/include/dmd/druntime/import";
        res ~= "/usr/include/dmd/phobos";
    }
    return res;
}

/// Stores info about project configuration
struct ProjectConfiguration {
    /// name used to build the project
    string name;
    /// type, for libraries one can run tests, for apps - execute them
    Type type;
    
    /// How to display default configuration in ui
    immutable static string DEFAULT_NAME = "default";
    /// Default project configuration
    immutable static ProjectConfiguration DEFAULT = ProjectConfiguration(DEFAULT_NAME, Type.Default);
    
    /// Type of configuration
    enum Type {
        Default,
        Executable,
        Library
    }
    
    private static Type parseType(string s)
    {
        switch(s)
        {
            case "executable": return Type.Executable;
            case "library": return Type.Library;
            case "dynamicLibrary": return Type.Library;
            case "staticLibrary": return Type.Library;
            default: return Type.Default;
        }
    }
    
    /// parsing from setting file
    static ProjectConfiguration[string] load(Setting s)
    {
        ProjectConfiguration[string] res = [DEFAULT_NAME: DEFAULT];
        Setting configs = s.objectByPath("configurations");
        if(configs is null || configs.type != SettingType.ARRAY) 
            return res;
        
        foreach(conf; configs) {
            if(!conf.isObject) continue;
            Type t = Type.Default;
            if(auto typeName = conf.getString("targetType"))
                t = parseType(typeName);
            if (string confName = conf.getString("name"))
                res[confName] = ProjectConfiguration(confName, t);
        }
        return res;
    }
}

/// DLANGIDE D project
class Project : WorkspaceItem {
    protected Workspace _workspace;
    protected bool _opened;
    protected ProjectFolder _items;
    protected ProjectSourceFile _mainSourceFile;
    protected SettingsFile _projectFile;
    protected ProjectSettings _settingsFile;
    protected bool _isDependency;
    protected string _dependencyVersion;

    protected string[] _sourcePaths;
    protected string[] _builderSourcePaths;
    protected ProjectConfiguration[string] _configurations;

    this(Workspace ws, string fname = null, string dependencyVersion = null) {
        super(fname);
        _workspace = ws;
        _items = new ProjectFolder(fname);
        _dependencyVersion = dependencyVersion;
        _isDependency = _dependencyVersion.length > 0;
        _projectFile = new SettingsFile(fname);
    }

    @property ProjectSettings settings() {
        if (!_settingsFile) {
            _settingsFile = new ProjectSettings(settingsFileName);
            _settingsFile.updateDefaults();
            _settingsFile.load();
            _settingsFile.save();
        }
        return _settingsFile;
    }

    @property string settingsFileName() {
        return buildNormalizedPath(dir, toUTF8(name) ~ ".settings");
    }

    @property bool isDependency() { return _isDependency; }
    @property string dependencyVersion() { return _dependencyVersion; }

    /// returns project configurations
    @property const(ProjectConfiguration[string]) configurations() const
    {
        return _configurations;
    }

    /// direct access to project file (json)
    @property SettingsFile content() { return _projectFile; }

    /// name
    override @property dstring name() {
        return super.name();
    }

    /// name
    override @property void name(dstring s) {
        super.name(s);
        _projectFile.setString("name", toUTF8(s));
    }

    /// name
    override @property dstring description() {
        return super.description();
    }

    /// name
    override @property void description(dstring s) {
        super.description(s);
        _projectFile.setString("description", toUTF8(s));
    }

    /// returns project's own source paths
    @property string[] sourcePaths() { return _sourcePaths; }
    /// returns project's own source paths
    @property string[] builderSourcePaths() { 
        if (!_builderSourcePaths) {
            _builderSourcePaths = dmdSourcePaths();
        }
        return _builderSourcePaths; 
    }

    ProjectSourceFile findSourceFile(string projectFileName, string fullFileName) {
        return _items ? _items.findSourceFile(projectFileName, fullFileName) : null;
    }

    private static void addUnique(ref string[] dst, string[] items) {
        foreach(item; items) {
            if (!canFind(dst, item))
                dst ~= item;
        }
    }
    @property string[] importPaths() {
        string[] res;
        addUnique(res, sourcePaths);
        addUnique(res, builderSourcePaths);
        foreach(dep; _dependencies) {
            addUnique(res, dep.sourcePaths);
        }
        return res;
    }

    string relativeToAbsolutePath(string path) {
        if (isAbsolute(path))
            return path;
        return buildNormalizedPath(_dir, path);
    }

    string absoluteToRelativePath(string path) {
        if (!isAbsolute(path))
            return path;
        return relativePath(path, _dir);
    }

    @property ProjectSourceFile mainSourceFile() { return _mainSourceFile; }
    @property ProjectFolder items() { return _items; }

    @property Workspace workspace() { return _workspace; }

    @property void workspace(Workspace p) { _workspace = p; }

    @property string defWorkspaceFile() {
        return buildNormalizedPath(_filename.dirName, toUTF8(name) ~ WORKSPACE_EXTENSION);
    }

    @property bool isExecutable() {
        // TODO: use targetType
        return true;
    }

    /// return executable file name, or null if it's library project or executable is not found
    @property string executableFileName() {
        if (!isExecutable)
            return null;
        string exename = toUTF8(name);
        exename = _projectFile.getString("targetName", exename);
        // TODO: use targetName
        version (Windows) {
            exename = exename ~ ".exe";
        }
        // TODO: use targetPath
        string exePath = buildNormalizedPath(_filename.dirName, "bin", exename);
        return exePath;
    }

    /// working directory for running and debugging project
    @property string workingDirectory() {
        // TODO: get from settings
        return _filename.dirName;
    }

    /// commandline parameters for running and debugging project
    @property string runArgs() {
        // TODO: get from settings
        return null;
    }

    @property bool runInExternalConsole() {
        // TODO
        return true;
    }

    ProjectFolder findItems(string[] srcPaths) {
        auto folder = new ProjectFolder(_filename);
        folder.project = this;
        string path = relativeToAbsolutePath("src");
        if (folder.loadDir(path))
            _sourcePaths ~= path;
        path = relativeToAbsolutePath("source");
        if (folder.loadDir(path))
            _sourcePaths ~= path;
        foreach(customPath; srcPaths) {
            path = relativeToAbsolutePath(customPath);
            foreach(existing; _sourcePaths)
                if (path.equal(existing))
                    continue; // already exists
            if (folder.loadDir(path))
                _sourcePaths ~= path;
        }
        return folder;
    }

    void refresh() {
        for (int i = _items._children.count - 1; i >= 0; i--) {
            if (_items._children[i].isFolder)
                _items._children[i].refresh();
        }
    }

    void findMainSourceFile() {
        string n = toUTF8(name);
        string[] mainnames = ["app.d", "main.d", n ~ ".d"];
        foreach(sname; mainnames) {
            _mainSourceFile = findSourceFileItem(buildNormalizedPath(_dir, "src", sname));
            if (_mainSourceFile)
                break;
            _mainSourceFile = findSourceFileItem(buildNormalizedPath(_dir, "source", sname));
            if (_mainSourceFile)
                break;
        }
    }

    /// tries to find source file in project, returns found project source file item, or null if not found
    ProjectSourceFile findSourceFileItem(ProjectItem dir, string filename, bool fullFileName=true) {
        foreach(i; 0 .. dir.childCount) {
            ProjectItem item = dir.child(i);
            if (item.isFolder) {
                ProjectSourceFile res = findSourceFileItem(item, filename, fullFileName);
                if (res)
                    return res;
            } else {
                auto res = cast(ProjectSourceFile)item;
                if(res)
                {
                    if(fullFileName && res.filename.equal(filename))
                        return res;
                    else if (!fullFileName && res.filename.endsWith(filename))
                        return res;
                }
            }
        }
        return null;
    }

    ProjectSourceFile findSourceFileItem(string filename, bool fullFileName=true) {
        return findSourceFileItem(_items, filename, fullFileName);
    }

    override bool load(string fname = null) {
        if (!_projectFile)
            _projectFile = new SettingsFile();
        _mainSourceFile = null;
        if (fname.length > 0)
            filename = fname;
        if (!_projectFile.load(_filename)) {
            Log.e("failed to load project from file ", _filename);
            return false;
        }
        Log.d("Reading project from file ", _filename);

        try {
            _name = toUTF32(_projectFile.getString("name"));
            if (_isDependency) {
                _name ~= "-"d;
                _name ~= toUTF32(_dependencyVersion.startsWith("~") ? _dependencyVersion[1..$] : _dependencyVersion);
            }
            _description = toUTF32(_projectFile.getString("description"));
            Log.d("  project name: ", _name);
            Log.d("  project description: ", _description);
            string[] srcPaths = _projectFile.getStringArray("sourcePaths");
            _items = findItems(srcPaths);
            findMainSourceFile();

            Log.i("Project source paths: ", sourcePaths);
            Log.i("Builder source paths: ", builderSourcePaths);
            if (!_isDependency)
                loadSelections();

            _configurations = ProjectConfiguration.load(_projectFile);
            Log.i("Project configurations: ", _configurations);
            
        } catch (Exception e) {
            Log.e("Cannot read project file", e);
            return false;
        }
        _items.loadFile(filename);
        return true;
    }

    override bool save(string fname = null) {
        if (fname !is null)
            filename = fname;
        assert(filename !is null);
        return _projectFile.save(filename, true);
    }

    protected Project[] _dependencies;
    @property Project[] dependencies() { return _dependencies; }

    Project findDependencyProject(string filename) {
        foreach(dep; _dependencies) {
            if (dep.filename.equal(filename))
                return dep;
        }
        return null;
    }

    bool loadSelections() {
        Project[] newdeps;
        _dependencies.length = 0;
        auto finder = new DubPackageFinder;
        scope(exit) destroy(finder);
        SettingsFile selectionsFile = new SettingsFile(buildNormalizedPath(_dir, "dub.selections.json"));
        if (!selectionsFile.load()) {
            _dependencies = newdeps;
            return false;
        }
        Setting versions = selectionsFile.objectByPath("versions");
        if (!versions.isObject) {
            _dependencies = newdeps;
            return false;
        }
        string[string] versionMap = versions.strMap;
        foreach(packageName, packageVersion; versionMap) {
            string fn = finder.findPackage(packageName, packageVersion);
            Log.d("dependency ", packageName, " ", packageVersion, " : ", fn ? fn : "NOT FOUND");
            if (fn) {
                Project p = findDependencyProject(fn);
                if (p) {
                    Log.d("Found existing dependency project ", fn);
                    newdeps ~= p;
                    continue;
                }
                p = new Project(_workspace, fn, packageVersion);
                if (p.load()) {
                    newdeps ~= p;
                    if (_workspace)
                        _workspace.addDependencyProject(p);
                } else {
                    Log.e("cannot load dependency package ", packageName, " ", packageVersion, " from file ", fn);
                    destroy(p);
                }
            }
        }
        _dependencies = newdeps;
        return true;
    }
}

class DubPackageFinder {
    string systemDubPath;
    string userDubPath;
    string tempPath;
    this() {
        version(Windows){
            systemDubPath = buildNormalizedPath(environment.get("ProgramData"), "dub", "packages");
            userDubPath = buildNormalizedPath(environment.get("APPDATA"), "dub", "packages");
            tempPath = buildNormalizedPath(environment.get("TEMP"), "dub", "packages");
        } else version(Posix){
            systemDubPath = "/var/lib/dub/packages";
            userDubPath = buildNormalizedPath(environment.get("HOME"), ".dub", "packages");
            if(!userDubPath.isAbsolute)
                userDubPath = buildNormalizedPath(getcwd(), userDubPath);
            tempPath = "/tmp/packages";
        }
    }

    protected string findPackage(string packageDir, string packageName, string packageVersion) {
        string fullName = packageVersion.startsWith("~") ? packageName ~ "-" ~ packageVersion[1..$] : packageName ~ "-" ~ packageVersion;
        string pathName = absolutePath(buildNormalizedPath(packageDir, fullName));
        if (pathName.exists && pathName.isDir) {
            string fn = buildNormalizedPath(pathName, "dub.json");
            if (fn.exists && fn.isFile)
                return fn;
            fn = buildNormalizedPath(pathName, "package.json");
            if (fn.exists && fn.isFile)
                return fn;
            // new DUB support - with package subdirectory
            fn = buildNormalizedPath(pathName, packageName, "dub.json");
            if (fn.exists && fn.isFile)
                return fn;
            fn = buildNormalizedPath(pathName, packageName, "package.json");
            if (fn.exists && fn.isFile)
                return fn;
        }
        return null;
    }

    string findPackage(string packageName, string packageVersion) {
        string res = null;
        res = findPackage(userDubPath, packageName, packageVersion);
        if (res)
            return res;
        res = findPackage(systemDubPath, packageName, packageVersion);
        return res;
    }
}

bool isValidProjectName(in string s) pure {
    if (s.empty)
        return false;
    return reduce!q{ a && (b == '_' || b == '-' || std.ascii.isAlphaNum(b)) }(true, s);
}

bool isValidModuleName(in string s) pure {
    if (s.empty)
        return false;
    return reduce!q{ a && (b == '_' || std.ascii.isAlphaNum(b)) }(true, s);
}

bool isValidFileName(in string s) pure {
    if (s.empty)
        return false;
    return reduce!q{ a && (b == '_' || b == '.' || b == '-' || std.ascii.isAlphaNum(b)) }(true, s);
}

unittest {
    assert(!isValidProjectName(""));
    assert(isValidProjectName("project"));
    assert(isValidProjectName("cool_project"));
    assert(isValidProjectName("project-2"));
    assert(!isValidProjectName("project.png"));
    assert(!isValidProjectName("[project]"));
    assert(!isValidProjectName("<project/>"));
    assert(!isValidModuleName(""));
    assert(isValidModuleName("module"));
    assert(isValidModuleName("awesome_module2"));
    assert(!isValidModuleName("module-2"));
    assert(!isValidModuleName("module.png"));
    assert(!isValidModuleName("[module]"));
    assert(!isValidModuleName("<module>"));
    assert(!isValidFileName(""));
    assert(isValidFileName("file"));
    assert(isValidFileName("file_2"));
    assert(isValidFileName("file-2"));
    assert(isValidFileName("file.txt"));
    assert(!isValidFileName("[file]"));
    assert(!isValidFileName("<file>"));
}

class EditorBookmark {
    string file;
    string fullFilePath;
    string projectFilePath;
    int line;
    string projectName;
}
