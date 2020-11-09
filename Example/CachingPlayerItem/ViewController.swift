//
//  ViewController.swift
//  CachingPlayerItem
//
//  Created by sukov on 10/24/2020.
//  Copyright (c) 2020 sukov. All rights reserved.
//

import UIKit
import AVKit
import CachingPlayerItem

class ViewController: UITableViewController {
    private var videos = [
        VideoModel(id: "1",
                   streamURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!,
                   fileExtension: "mp4",
                   thumbnailURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/c/c5/Big_buck_bunny_poster_big.jpg")!),
    ]

    private lazy var downloadProgressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.trackTintColor = UIColor(white: 1, alpha: 0)
        progressView.progressTintColor = .blue
        progressView.frame = CGRect(x: 0,
                                    y: (navigationController?.navigationBar.frame.size.height ?? 0) - progressView.frame.size.height,
                                    width: (navigationController?.navigationBar.frame.size.width ?? 0),
                                    height: progressView.frame.size.height)
        return progressView
    }()

    private let cellReuseID = String(describing: UITableViewCell.self)

    override func viewDidLoad() {
        super.viewDidLoad()

        setupNavigationBar()
        setupView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.navigationBar.addSubview(downloadProgressView)
    }
}

private extension ViewController {
    func setupNavigationBar() {
        navigationItem.title = "CachingPlayerItem Example"
    }

    func setupView() {
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseID)
    }

    func animateProgressViewToCompletion() {
        UIView.animate(withDuration: 0.3, delay: 0.4, options: .curveEaseOut, animations: {
            self.downloadProgressView.alpha = 0
        }, completion: { _ in
            self.downloadProgressView.setProgress(0, animated: false)
        })
    }
}

// MARK: - CachingPlayerItemDelegate

extension ViewController: CachingPlayerItemDelegate {
    func playerItemReadyToPlay(_ playerItem: CachingPlayerItem) {
        guard let video = playerItem.playable as? VideoModel else { return }

        print("Caching player item ready to play for \(video.id).")
    }

    func playerItemDidFailToPlay(_ playerItem: CachingPlayerItem, withError error: Error?) {
        guard let _ = playerItem.playable as? VideoModel else { return }

        print(error?.localizedDescription ?? "")
    }

    func playerItemPlaybackStalled(_ playerItem: CachingPlayerItem) {
        print("Caching player item stalled.")
    }

    func playerItem(_ playerItem: CachingPlayerItem, didDownloadBytesSoFar bytesDownloaded: Int, outOf bytesExpected: Int) {
        downloadProgressView.alpha = 1.0
        downloadProgressView.setProgress(Float(Double(bytesDownloaded) / Double(bytesExpected)), animated: true)
    }

    func playerItem(_ playerItem: CachingPlayerItem, didFinishDownloadingFileAt filePath: String) {
        animateProgressViewToCompletion()

        print("Caching player item file downloaded.")
    }

    func playerItem(_ playerItem: CachingPlayerItem, downloadingFailedWith error: Error) {
        animateProgressViewToCompletion()

        print("Caching player item file download failed with error: \(error.localizedDescription).")
    }
}


// MARK: - TableViewDataSource

extension ViewController {
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return videos.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseID, for: indexPath)

        cell.accessoryType = .disclosureIndicator
        cell.textLabel?.text = videos[indexPath.row].id

        return cell
    }
}

// MARK: - TableViewDelegate

extension ViewController {
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let avViewController = AVPlayerViewController()

        let item = CachingPlayerItem(model: videos[indexPath.row])
        item.delegate = self

        avViewController.player = AVPlayer(playerItem: item)
        avViewController.player?.automaticallyWaitsToMinimizeStalling = false
        avViewController.player?.play()

        navigationController?.pushViewController(avViewController, animated: true)
    }
}
