import Cocoa
import WebKit
import Foundation

let TENOR_BASE_URL = "https://tenor.com/"
let TENOR_VIEW_URL = "https://tenor.com/view/"
let TENOR_FAVICON_URL = "https://tenor.com/favicon.ico"

let MARKDOWN_PREFIX = "![]("
let MARKDOWN_SUFFIX = ")"

let STATUS_ITEM_TITLE = "Tenor Anywhere"
let COPY_URL_MENU_ITEM_TITLE = "Copy GIF URL"
let COPY_MARKDOWN_MENU_ITEM_TITLE = "Copy GIF URL (GitHub Markdown)"
let COPY_IMAGE_MENU_ITEM_TITLE = "Copy GIF as Image"
let QUIT_MENU_ITEM_TITLE = "Quit"

let URL_KEY_PATH = "URL"


// Function to extract a meta tag's content from HTML
func extractMetaTagContent(from html: String, property: String) -> String? {
    let pattern = "<meta property=\"\(property)\" content=\"([^\"]+)\""
    
    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
       let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) {
        
        if let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }
    }
    
    return nil
}
func fetchImageURL(from url: URL, completion: @escaping (String?) -> Void) {
    URLSession.shared.dataTask(with: url) { data, response, error in
        guard let data = data, let html = String(data: data, encoding: .utf8) else {
            completion(nil)
            return
        }

        // Regex to match <meta itemprop="contentUrl" content="URL">
        let pattern = #"<meta\s+itemprop="contentUrl"\s+content="([^"]+)""#
        if let range = html.range(of: pattern, options: .regularExpression),
           let match = html[range].range(of: #"https?://[^"]+"#, options: .regularExpression) {
            let imageUrl = String(html[match])
            completion(imageUrl)
        } else {
            completion(nil)
        }
    }.resume()
}


func gifURL(url: URL?) -> String? {
    guard let string = url?.absoluteString else { return nil }
    if (!string.starts(with: TENOR_VIEW_URL)) { return nil }
    return string + ".gif";
}

func gifMarkdown(url: URL?) -> String? {
    guard let url = gifURL(url: url) else { return nil }
    return MARKDOWN_PREFIX + url + MARKDOWN_SUFFIX
}

func getTenorImage() -> NSImage? {
    guard let path = Bundle.main.pathForImageResource("tenor") else { return nil }
    guard let image = NSImage.init(byReferencingFile: path) else { return nil }
    image.isTemplate = true
    image.size = NSSize(width: 24, height: 24)
    return image;
}

func getiPhoneWebView() -> WKWebView {
    let webViewRect = NSMakeRect(0, 0, 360, 640)
    let webViewConf = WKWebViewConfiguration.init()
    webViewConf.preferences.plugInsEnabled = true
    let webView = WKWebView.init(frame: webViewRect, configuration: webViewConf)
    return webView
}

func setPasteboard(string: String?) {
    guard let string = string else { NSSound.beep(); return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}

class MainController: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    
    class func run() {
        let app = NSApplication.shared
        let mainController = MainController.init()
        app.delegate = mainController
        app.run()
    }
    
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let statusMenu = NSMenu.init()
    let url = URL.init(string: TENOR_BASE_URL)!
    let webView = getiPhoneWebView()
    let webViewItem = NSMenuItem.init()
    let copyURLItem = NSMenuItem.init()
    let copyMarkdownItem = NSMenuItem.init()
    let copyImageItem = NSMenuItem.init()
    let quitItem = NSMenuItem.init()
    
    override init() {
        super.init()
        setLoginItem(enabled: true)
        setupStatusItem()
        setupStatusMenu()
        setupWebView()
    }
    
    func setupStatusItem() {
        let tenorImage = getTenorImage()
        if let tenorImage = tenorImage {
            statusItem.button?.image = tenorImage
        }
        else {
            statusItem.button?.title = STATUS_ITEM_TITLE
        }
        statusItem.button?.target = self
        statusItem.button?.action = #selector(MainController.statusItemClicked(_:))
        statusItem.button?.highlight(false)
    }
    
    func setupStatusMenu() {
        webViewItem.view = webView
        copyURLItem.title = COPY_URL_MENU_ITEM_TITLE
        copyURLItem.target = self
        copyURLItem.action = #selector(MainController.copyURL(_:))
        copyMarkdownItem.title = COPY_MARKDOWN_MENU_ITEM_TITLE
        copyMarkdownItem.target = self
        copyMarkdownItem.action = #selector(MainController.copyMarkdown(_:))
        copyImageItem.title = COPY_IMAGE_MENU_ITEM_TITLE
        copyImageItem.target = self
        copyImageItem.action = #selector(MainController.copyImage(_:))
        quitItem.title = QUIT_MENU_ITEM_TITLE
        quitItem.target = self
        quitItem.action = #selector(MainController.quit(_:))
        statusMenu.addItem(webViewItem)
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(copyURLItem)
        statusMenu.addItem(copyMarkdownItem)
        statusMenu.addItem(copyImageItem)
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(quitItem)
    }
    
    func setupWebView() {
        webView.navigationDelegate = self
        webView.addObserver(self, forKeyPath: URL_KEY_PATH, options: .new, context: nil)
        reloadWebView()
    }
    
    func reloadWebView() {
        webView.load(URLRequest.init(url: url))
    }
    
    func popUpStatusItem() {
        statusItem.menu = statusMenu
        statusItem.button?.performClick(self)
        statusItem.menu = nil
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        popUpStatusItem()
    }
    
    func copyImageFromURL(_ url: String?) {
        guard let url = url, let imageURL = URL(string: url) else { return }
        
        let task = URLSession.shared.dataTask(with: imageURL) { data, response, error in
            if let error = error {
                print("Failed to load image: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("Invalid image data")
                return
            }
            
            DispatchQueue.main.async {
                do {
                    // Create a temporary file path
                    let tempDir = FileManager.default.temporaryDirectory
                    let tempFileURL = tempDir.appendingPathComponent("copied_gif.gif")
                    
                    // Write GIF data to file
                    try data.write(to: tempFileURL)
                    
                    // Copy file reference to clipboard
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setData(tempFileURL.dataRepresentation, forType: .fileURL)
                    
                    print("GIF copied successfully! File path: \(tempFileURL.path)")
                } catch {
                    print("Error saving GIF: \(error)")
                }
            }
        }
        
        task.resume()
    }


    func fetchGIFURLFromTenorPage(_ url: URL?) {
//        guard let url = URL(string: pageURL) else { return }
        guard let url: URL = url else { return }
        fetchImageURL(from: url, completion: copyImageFromURL)
    }
    
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(MainController.copyURL(_:)),
             #selector(MainController.copyMarkdown(_:)):
            return gifURL(url: webView.url) != nil
        default:
            return true
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        let enabled = gifURL(url: webView.url) != nil
        copyURLItem.isEnabled = enabled
        copyMarkdownItem.isEnabled = enabled
    }
    
    @objc func statusItemClicked(_ sender: AnyObject) {
        NSApp.isActive ?
            popUpStatusItem() : NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func copyURL(_ sender: AnyObject) {
        setPasteboard(string: gifURL(url: webView.url))
    }
    
    @objc func copyMarkdown(_ sender: AnyObject) {
        setPasteboard(string: gifMarkdown(url: webView.url))
    }
    
    @objc func copyImage(_ sender: AnyObject) {
        fetchGIFURLFromTenorPage(webView.url)
    }
    
    @objc func quit(_ sender: AnyObject) {
        setLoginItem(enabled: false)
        NSApp.terminate(sender)
    }
    
}
