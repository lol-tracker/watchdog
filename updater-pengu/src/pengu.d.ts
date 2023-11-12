interface PenguRCP {
  preInit(name: string, callback: (provider: any) => any)
  postInit(name: string, callback: (api: any) => any)
  whenReady(name: string): Promise<any>
  whenReady(names: string[]): Promise<any[]>
}

interface PenguContext {
	readonly rcp: PenguRCP
}

interface FileStat {
  fileName: string
  length: number
  isDir: boolean
}

interface PluginFS {
  read: (path: string) => Promise<string | undefined>
  write: (path: string, content: string, enableAppendMode: boolean) => Promise<boolean>
  mkdir: (path: string) => Promise<boolean>
  stat: (path: string) => Promise<FileStat | undefined>
  ls: (path: string) => Promise<string[] | undefined>
  rm: (path: string, recursively: boolean) => Promise<number>
}

declare const PluginFS: PluginFS;
declare const getScriptPath: () => string | undefined;

declare interface Window {
  PluginFS: PluginFS;
  getScriptPath: typeof getScriptPath;
}
