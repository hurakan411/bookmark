# iOS Share Extension セットアップ手順

このファイルは、Share Extensionを有効にするためのXcodeでの手動設定手順を説明します。

## 1. Xcodeでプロジェクトを開く

```bash
cd ios
open Runner.xcworkspace
```

## 2. Share Extension Targetを追加

1. Xcodeのプロジェクトナビゲータで「Runner」プロジェクトを選択
2. メニューから **File > New > Target...** を選択
3. **iOS > Application Extension > Share Extension** を選択して「Next」
4. 以下の設定を入力：
   - **Product Name**: `ShareExtension`
   - **Team**: 自分の開発チームを選択
   - **Organization Identifier**: `com.hashinokuchi.bookmark`（Runnerと同じ）
   - **Language**: Swift
   - **Project**: Runner
   - **Embed in Application**: Runner
5. 「Finish」をクリック
6. 「Activate "ShareExtension" scheme?」と聞かれたら **Activate** を選択

## 3. ShareExtensionのファイルを置き換える

Xcodeで生成されたデフォルトのファイルを、すでに作成済みのファイルに置き換えます：

1. Xcodeのプロジェクトナビゲータで `ShareExtension` フォルダを展開
2. 以下のファイルを削除（右クリック > Delete > Move to Trash）：
   - `ShareViewController.swift`（自動生成されたもの）
   - `MainInterface.storyboard`（自動生成されたもの）
   - `Info.plist`（自動生成されたもの）

3. すでに作成済みのファイルを追加：
   - プロジェクトナビゲータの `ShareExtension` フォルダを右クリック
   - **Add Files to "Runner"...** を選択
   - `ios/ShareExtension` フォルダ内の以下のファイルを選択：
     - `ShareViewController.swift`
     - `MainInterface.storyboard`
     - `Info.plist`
   - **Options** で以下を確認：
     - ☑ Copy items if needed（必要に応じて）
     - ☑ Add to targets: ShareExtension にチェック
   - 「Add」をクリック

## 4. App Groupsを設定

Share Extensionとメインアプリでデータを共有するため、App Groupsを設定します。

### 4.1 RunnerのApp Groups

1. プロジェクトナビゲータで「Runner」プロジェクトを選択
2. TARGETSから「Runner」を選択
3. 「Signing & Capabilities」タブを選択
4. 「+ Capability」ボタンをクリック
5. 「App Groups」を選択
6. 「+」ボタンをクリックして以下のGroup IDを追加：
   ```
   group.com.hashinokuchi.bookmark
   ```

### 4.2 ShareExtensionのApp Groups

1. TARGETSから「ShareExtension」を選択
2. 「Signing & Capabilities」タブを選択
3. 「+ Capability」ボタンをクリック
4. 「App Groups」を選択
5. 「+」ボタンをクリックして以下のGroup IDを追加（Runnerと同じ）：
   ```
   group.com.hashinokuchi.bookmark
   ```

## 5. ShareExtensionのBundle Identifierを設定

1. TARGETSから「ShareExtension」を選択
2. 「General」タブを選択
3. 「Identity」セクションで **Bundle Identifier** が以下になっていることを確認：
   ```
   com.hashinokuchi.bookmark.ShareExtension
   ```

## 6. デプロイメントターゲットを設定

1. TARGETSから「ShareExtension」を選択
2. 「General」タブを選択
3. 「Deployment Info」セクションで **iOS Deployment Target** を **14.0** 以上に設定（Runnerと同じバージョン）

## 7. ビルドして実行

1. Xcodeで「Runner」スキームを選択
2. シミュレータまたは実機を選択
3. ビルドして実行（Cmd + R）

## 8. 動作確認

1. iOS SimulatorまたはiOS実機でSafariを開く
2. 任意のWebページを開く
3. 共有ボタン（四角に上向き矢印）をタップ
4. 「Save to Bookmarks」（または「ブックマークに保存」）を選択
5. ブックマークアプリが開き、新規ブックマーク追加画面が表示される

## トラブルシューティング

### Share Extensionが共有メニューに表示されない場合

1. 共有メニューの一番下までスクロール
2. 「その他」または「編集」をタップ
3. 「Save to Bookmarks」を有効にする

### ビルドエラーが出る場合

- Clean Build Folder（Shift + Cmd + K）を実行
- Xcodeを再起動
- Derivedデータを削除：`rm -rf ~/Library/Developer/Xcode/DerivedData`

### App Groupsでデータが共有されない場合

- RunnerとShareExtension両方で同じGroup IDが設定されているか確認
- プロビジョニングプロファイルにApp Groups Capabilityが含まれているか確認（実機の場合）

## 注意事項

- **実機でテストする場合**：Apple Developer Programへの登録が必要です
- **App Groups**：実機では開発者アカウントで適切なプロビジョニングプロファイルが必要です
- **Bundle Identifier**：`com.hashinokuchi.bookmark` を自分のドメインに変更してください
