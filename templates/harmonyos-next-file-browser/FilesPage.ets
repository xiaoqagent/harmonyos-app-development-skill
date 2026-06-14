/**
 * 文件浏览页面模板。
 * 使用方式：
 * 1. 复制到项目 entry/src/main/ets/pages/FilesPage.ets
 * 2. 在 main_pages.json 中添加 "pages/FilesPage"
 * 3. 从 ChatPage 跳转：router.pushUrl({ url: 'pages/FilesPage' })
 *
 * 依赖：FileApi.ets（放在 utils/ 目录下）
 * 后端：xiaoq-api (GET /api/files?path=, GET /api/files/read?path=)
 *
 * 行为：面包屑导航 + 文件列表，点击目录进入，点击文件阅读。
 */

import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { FileApi, FileItem, FileListResult } from '../utils/FileApi.ets';

const PUBLIC_API: string = 'https://xiaoq.xiao-q.com';

interface NavItem {
  name: string;
  path: string;
  key: string;
}

@Entry
@Component
struct FilesPage {
  @State currentItems: FileItem[] = [];
  @State isLoading: boolean = true;
  @State navStack: NavItem[] = [];
  @State titleText: string = '知识库';

  private fileApi: FileApi = new FileApi(PUBLIC_API, '');

  aboutToAppear(): void {
    const savedKey: string = AppStorage.get<string>('apiKey') as string;
    if (savedKey !== undefined) {
      this.fileApi.updateConfig(PUBLIC_API, savedKey);
    }
    this.navStack = [{ name: '知识库', path: '', key: 'root' }];
    this.loadDir('');
  }

  private async loadDir(dirPath: string): Promise<void> {
    this.isLoading = true;
    try {
      const result: FileListResult = await this.fileApi.listFiles(dirPath);
      this.currentItems = result.items;
      this.titleText = dirPath === '' ? '知识库' : dirPath.split('/').pop() ?? '';
    } catch (error) {
      promptAction.showToast({ message: (error instanceof Error) ? (error as Error).message : '加载失败', duration: 2000 });
      this.currentItems = [];
    } finally {
      this.isLoading = false;
    }
  }

  private enterDir(item: FileItem): void {
    this.navStack.push({ name: item.name, path: item.path, key: item.path });
    this.loadDir(item.path);
  }

  private goBack(): void {
    if (this.navStack.length <= 1) { router.back(); return; }
    this.navStack.pop();
    this.loadDir(this.navStack[this.navStack.length - 1].path);
  }

  private openFile(item: FileItem): void {
    router.pushUrl({ url: 'pages/FileViewPage', params: { filePath: item.path, fileName: item.name } as Record<string, Object> });
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Button() { Text('← ' + (this.navStack.length > 1 ? '返回' : '聊天')).fontSize(15).fontColor('#5B5BD6') }
          .backgroundColor('transparent').onClick(() => { this.goBack(); })
        Blank()
        Text(this.titleText).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#1A1A2E')
        Blank()
        Text('').fontSize(15).width(60)
      }.width('100%').padding({ left: 8, right: 16, top: 8, bottom: 8 }).backgroundColor('#F8F9FF')

      // 面包屑
      if (this.navStack.length > 1) {
        Scroll() {
          Row() {
            ForEach(this.navStack, (nav: NavItem, idx: number) => {
              Text((idx > 0 ? ' / ' : '') + nav.name)
                .fontSize(12).fontColor(idx === this.navStack.length - 1 ? '#5B5BD6' : '#999999')
                .onClick(() => {
                  while (this.navStack.length > idx + 1) this.navStack.pop();
                  this.loadDir(nav.path);
                })
            }, (nav: NavItem) => nav.key)
          }.padding({ left: 16, right: 16, top: 6, bottom: 6 })
        }.scrollBar(BarState.Off).height(32).backgroundColor('#F0F0F5').width('100%')
      }

      // 内容区
      if (this.isLoading) {
        Column() { LoadingProgress().width(40).height(40).color('#5B5BD6')
          Text('加载中...').fontSize(14).fontColor('#999999').margin({ top: 12 }) }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.currentItems.length === 0) {
        Column() { Text('📂').fontSize(48); Text('空目录').fontSize(15).fontColor('#999999').margin({ top: 8 }) }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.currentItems, (item: FileItem) => {
            ListItem() {
              Row() {
                Text(this.getIcon(item)).fontSize(22).margin({ right: 12 })
                Column() {
                  Text(item.name).fontSize(15).fontColor('#1A1A2E').lineHeight(22)
                  Text(item.type === 'directory' ? '文件夹' : '文件').fontSize(11).fontColor('#BBBBBB')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(item.type === 'directory' ? '›' : '').fontSize(20).fontColor('#CCCCCC')
              }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .backgroundColor('#FFFFFF').borderRadius(10)
                .onClick(() => { item.type === 'directory' ? this.enterDir(item) : this.openFile(item); })
            }
          }, (item: FileItem) => item.path)
        }.width('100%').layoutWeight(1).backgroundColor('#F5F5FA').padding({ top: 8, bottom: 8 })
      }
    }.width('100%').height('100%').backgroundColor('#F5F5FA')
  }

  private getIcon(item: FileItem): string {
    if (item.type === 'directory') return '📁';
    const n: string = item.name.toLowerCase();
    if (n.endsWith('.md')) return '📝';
    if (n.endsWith('.json') || n.endsWith('.yaml')) return '⚙️';
    if (n.endsWith('.py') || n.endsWith('.ts')) return '💻';
    return '📄';
  }
}
