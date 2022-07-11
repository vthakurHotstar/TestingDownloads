/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 `AssetListTableViewController` is the main interface of this sample.  It provides a list of the assets the sample can
 play, download, cancel download, and delete.  To play an item, tap on the tableViewCell, to interact with the download
 APIs, long press on the cell and you will be provided options based on the download state associated with the Asset on
 the cell.
 */

import UIKit
import AVFoundation
import AVKit

class AssetListTableViewController: UITableViewController {
    // MARK: Properties
    
    static let presentPlayerViewControllerSegueID = "PresentPlayerViewControllerSegueIdentifier"
    
    fileprivate var playerViewController: AVPlayerViewController?
    
    private var pendingContentKeyRequests = [String: Asset]()
    
    // MARK: Deinitialization
    
    deinit {
        NotificationCenter.default.removeObserver(self,
                                                  name: .AssetListManagerDidLoad,
                                                  object: nil)
    }
    
    // MARK: UIViewController
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // General setup for auto sizing UITableViewCells.
        tableView.estimatedRowHeight = 75.0
        tableView.rowHeight = UITableViewAutomaticDimension
        
        // Set AssetListTableViewController as the delegate for AssetPlaybackManager to recieve playback information.
        AssetPlaybackManager.sharedManager.delegate = self
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleAssetListManagerDidLoad(_:)),
                                               name: .AssetListManagerDidLoad, object: nil)
        
        #if os(iOS)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(handleContentKeyDelegateDidSaveAllPersistableContentKey(notification:)),
                                                   name: .DidSaveAllPersistableContentKey,
                                                   object: nil)
        #endif
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if playerViewController != nil {
            // The view reappeared as a results of dismissing an AVPlayerViewController.
            // Perform cleanup.
            AssetPlaybackManager.sharedManager.setAssetForPlayback(nil)
            playerViewController?.player = nil
            playerViewController = nil
        }
    }
    
    // MARK: - Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return AssetListManager.sharedManager.numberOfAssets()
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: AssetListTableViewCell.reuseIdentifier, for: indexPath)
        
        let asset = AssetListManager.sharedManager.asset(at: indexPath.row)
        
        if let cell = cell as? AssetListTableViewCell {
            cell.asset = asset
            cell.delegate = self
        }
        
        return cell
    }
    
#if os(iOS)
    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) as? AssetListTableViewCell, let asset = cell.asset else { return }
        
        let downloadState = AssetPersistenceManager.sharedManager.downloadState(for: asset)
        let alertAction: UIAlertAction
        
        switch downloadState {
        case .notDownloaded:
            alertAction = UIAlertAction(title: "Download", style: .default) { _ in
                if asset.stream.isProtected {
                    self.pendingContentKeyRequests[asset.stream.name] = asset
                    
                    ContentKeyManager.shared.contentKeyDelegate.requestPersistableContentKeys(forAsset: asset)
                } else {
                    AssetPersistenceManager.sharedManager.downloadStream(for: asset)
                }
            }
            
        case .downloading:
            alertAction = UIAlertAction(title: "Cancel", style: .default) { _ in
                AssetPersistenceManager.sharedManager.cancelDownload(for: asset)
            }
            
        case .downloaded:
            alertAction = UIAlertAction(title: "Delete", style: .default) { _ in
//                AssetPersistenceManager.sharedManager.deleteAsset(asset)
//
//                if asset.stream.isProtected {
//                    ContentKeyManager.shared.contentKeyDelegate.deleteAllPeristableContentKeys(forAsset: asset)
//                }
                let playerItem = AVPlayerItem(asset: asset.urlAsset)
                let player = AVPlayer(playerItem: playerItem)
                let playerViewController = AVPlayerViewController()
                playerViewController.player = player
                self.present(playerViewController, animated: true, completion: {
                    player.play()
                    player.replaceCurrentItem(with: playerItem)
                })
                playerItem.observe(\AVPlayerItem.status, options: [.new, .initial]) { [weak self] item, temp in
                    guard let strongSelf = self else { return }

                    print(
                        "Item is :: ",
                        item.status.rawValue,
                        item.error,
                        temp.oldValue,
                        temp.newValue,
                        separator: ", "
                    )
                }

            }
        }
        
        let alertController = UIAlertController(title: asset.stream.name, message: "Select from the following options:", preferredStyle: .actionSheet)
        alertController.addAction(alertAction)
        alertController.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler: nil))
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            guard let popoverController = alertController.popoverPresentationController else {
                return
            }
            
            popoverController.sourceView = cell
            popoverController.sourceRect = cell.bounds
        }
        
        present(alertController, animated: true, completion: nil)
    }
#endif
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        
        if segue.identifier == AssetListTableViewController.presentPlayerViewControllerSegueID {
            guard let cell = sender as? AssetListTableViewCell,
                let playerViewControler = segue.destination as? AVPlayerViewController,
                let asset = cell.asset else { return }
            
            // Grab a reference for the destinationViewController to use in later delegate callbacks from AssetPlaybackManager.
            playerViewController = playerViewControler
            
            #if os(iOS)
                if AssetPersistenceManager.sharedManager.downloadState(for: asset) == .downloaded {
                    if !asset.urlAsset.resourceLoader.preloadsEligibleContentKeys {
                        asset.urlAsset.resourceLoader.preloadsEligibleContentKeys = true
                    }
                }
            #endif
            
            // Load the new Asset to playback into AssetPlaybackManager.
            //AssetPlaybackManager.sharedManager.setAssetForPlayback(asset)
            
        }
    }
    
    // MARK: Notification handling
    
    @objc
    func handleAssetListManagerDidLoad(_: Notification) {
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
#if os(iOS)
    @objc
    func handleContentKeyDelegateDidSaveAllPersistableContentKey(notification: Notification) {
        guard let assetName = notification.userInfo?["name"] as? String,
            let asset = self.pendingContentKeyRequests.removeValue(forKey: assetName) else {
            return
        }
        
        AssetPersistenceManager.sharedManager.downloadStream(for: asset)
    }
#endif
}

/**
 Extend `AssetListTableViewController` to conform to the `AssetListTableViewCellDelegate` protocol.
 */
extension AssetListTableViewController: AssetListTableViewCellDelegate {
    
    func assetListTableViewCell(_ cell: AssetListTableViewCell, downloadStateDidChange newState: Asset.DownloadState) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }
}

/**
 Extend `AssetListTableViewController` to conform to the `AssetPlaybackDelegate` protocol.
 */
extension AssetListTableViewController: AssetPlaybackDelegate {
    func streamPlaybackManager(_ streamPlaybackManager: AssetPlaybackManager, playerReadyToPlay player: AVPlayer) {
        //player.play()
    }
    
    func streamPlaybackManager(_ streamPlaybackManager: AssetPlaybackManager, playerCurrentItemDidChange player: AVPlayer) {
        guard let playerViewController = playerViewController, player.currentItem != nil else { return }
        
        playerViewController.player = player
    }
}
