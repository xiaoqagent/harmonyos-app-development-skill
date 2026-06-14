/**
 * 文件阅读页面模板。
 * 使用方式：
 * 1. 复制到项目 entry/src/main/ets/pages/FileViewPage.ets
 * 2. 在 main_pages.json 中添加 "pages/FileViewPage"
 * 3. 从 FilesPage 打开文件：router.pushUrl({ url: 'pages/FileViewPage', params: {filePath, fileName} })
 *
 * 显示纯文本内容，支持 .md / .json / .txt / .yaml 等文本格式。
 */

import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { FileApi } from '../utils/FileApi.ets';

const PUBLIC_API: string = 'https://xiaoq.xiao-q.com';

@Entry
@Component
struct FileViewPage {
  @State fileContent: string = '';
  @State isLoading: boolean = true;
  @State fileName: string = '';

  private fileApi: FileApi = new FileApi(PUBLIC_API, '');
  private filePath: string = '';

  aboutToAppear(): void {
    const params: Record<string, Object> = router.getParams() as Record<string, Object>;
    if (params !== undefined) {
      this.filePath = params['filePath'] as string;
      this.fileName = params['fileName'] as string;
    }
    this.loadContent();
  }

  private async loadContent(): Promise<void> {
    this.isLoading = true;
    try {
      const savedKey: string = AppStorage.get<string>('apiKey') as string;
      this.fileApi.updateConfig(PUBLIC_API, savedKey ?? '');
      this.fileContent = await this.fileApi.readFile(this.filePath);
    } catch (error) {
      const msg: string = (error instanceof Error) ? (error as Error).message : '读取失败';
      this.fileContent = '❌ ' + msg;
      promptAction.showToast({ message: msg, duration: 2000 });
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column() {
      Row() {
        Button() { Text('← 返回').fontSize(15).fontColor('#5B5BD6') }
          .backgroundColor('transparent').onClick(() => { router.back(); })
        Blank()
        Text(this.fileName).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#1A1A2E')
          .layoutWeight(1).textAlign(TextAlign.Center).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank(); Text('').fontSize(15).width(60)
      }.width('100%').padding({ left: 8, right: 16, top: 8, bottom: 8 }).backgroundColor('#F8F9FF')

      if (this.isLoading) {
        Column() { LoadingProgress().width(40).height(40).color('#5B5BD6')
          Text('加载中...').fontSize(14).fontColor('#999999').margin({ top: 12 }) }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Text(this.fileContent).fontSize(14).fontColor('#333333').lineHeight(24)
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 24 })
        }.scrollBar(BarState.Auto).width('100%').layoutWeight(1).backgroundColor('#FFFFFF')
      }
    }.width('100%').height('100%').backgroundColor('#F5F5FA')
  }
}
