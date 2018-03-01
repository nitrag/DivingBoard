//
//  PhotoCollectionViewController.swift
//  UnsplashPickerController
//
//  Created by Jim Rhoades on 2/15/18.
//  Copyright © 2018 Crush Apps. All rights reserved.
//

import UIKit

private let reuseIdentifier = "Cell"

class PhotoCollectionViewController: UICollectionViewController {
    
    var clientID = ""
    weak var delegate: UnsplashPickerControllerDelegate?
    var topInsetAdjustment: CGFloat = 0
    var collectionType: CollectionType = .new
    let cellSpacing: CGFloat = 2 // spacing between the photo thumbnails
    var loadingView: LoadingView?
    var photos: [UnsplashPhoto] = []
    var pageNumber = 1
    var searchBar: UISearchBar? // gets set during prepareForSegue in the ContainerViewController
    var currentSearchPhrase: String?
    var currentSearchTotalPages: Int = 0
    let sectionHeaderIdentifier = "SectionHeader"
    
    var currentLayoutStyle: LayoutStyle = .grid {
        didSet {
            collectionViewLayout.invalidateLayout()
        }
    }
    
    // MARK: - View lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // adjust insets to make room for the collectionTypePickerView
        collectionView?.contentInset.top += topInsetAdjustment
        collectionView?.scrollIndicatorInsets.top += topInsetAdjustment
        
        // hide navigation bar when scrolling down
        navigationController?.hidesBarsOnSwipe = true
        
        if collectionType == .search {
            configureToShowSearchBar()
        } else {
            // display a loading indicator
            loadingView = LoadingView()
            view.addCenteredSubview(view: loadingView!)
            
            // load photos from Unsplash
            loadPhotos()
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Photo loading
    
    func loadPhotos() {
        guard let url = unsplashURL(withSearchPhrase: currentSearchPhrase) else {
            return
        }
        
        print(url.absoluteString)
        
        let dataTask = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            
            // remove the loadingView regardless of whether or not there was an error
            DispatchQueue.main.async {
                if let loadingView = self?.loadingView {
                    UIView.animate(withDuration: 0.15, animations: {
                        loadingView.alpha = 0.0
                    }, completion: { completed in
                        loadingView.removeFromSuperview()
                    })
                }
            }
            
            guard let responseData = data else {
                print("Error: did not receive data")
                return
            }
            
            guard error == nil else {
                print(error!)
                return
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                var newPhotos: [UnsplashPhoto]
                
                if self?.collectionType == .search {
                    let searchResults = try decoder.decode(UnsplashSearchResults.self, from: responseData)
                    newPhotos = searchResults.results
                    self?.currentSearchTotalPages = searchResults.totalPages
                } else {
                    newPhotos = try decoder.decode([UnsplashPhoto].self, from: responseData)
                }
                self?.photos.append(contentsOf: newPhotos)
                
                DispatchQueue.main.async {
                    self?.collectionView?.reloadData()
                }
            } catch {
                print("error trying to convert data to JSON: \(error)")
                
                // handle common errors
                if let jsonString = String(data: responseData, encoding: .utf8) {
                    print(jsonString)
                    
                    var errorMessage = "Unknown error"
                    if jsonString == "Rate Limit Exceeded" {
                        errorMessage = NSLocalizedString("Rate Limit Exceeded",
                                                         comment: "error message shown when the Unsplash API rate limit has been exceeded")
                    } else if jsonString.contains("The access token is invalid") {
                        errorMessage = NSLocalizedString("The access token is invalid",
                                                         comment: "error message shown when an incorrect application ID has been used to access the Unsplash API")
                    }
                    self?.showErrorAlert(message: errorMessage)
                }
            }
        }
        
        dataTask.resume()
    }
    
    private func showErrorAlert(message: String) {
        let alertTitle = NSLocalizedString("Error", comment: "title of 'Error' alert")
        let alertController = UIAlertController(title: alertTitle, message: message, preferredStyle: .alert)
        let okTitle = NSLocalizedString("OK", comment: "'OK' button title")
        let okAction = UIAlertAction(title: okTitle, style: .default, handler: nil)
        alertController.addAction(okAction)
        present(alertController, animated: true, completion: nil)
    }
    
    private func unsplashURL(withSearchPhrase searchPhrase: String?) -> URL? {
        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host = "api.unsplash.com"
        
        switch collectionType {
        case .new:
            urlComponents.path = "/photos"
        case .curated:
            urlComponents.path = "/photos/curated"
        case .search:
            urlComponents.path = "/search/photos"
        }
        
        let clientIDItem = URLQueryItem(name: "client_id", value: clientID)
        let perPageItem = URLQueryItem(name: "per_page", value: "30")
        let pageNumberItem = URLQueryItem(name: "page", value: "\(pageNumber)")
        urlComponents.queryItems = [clientIDItem, perPageItem, pageNumberItem]
        
        if collectionType == .search {
            if let searchPhrase = currentSearchPhrase {
                let queryItem = URLQueryItem(name: "query", value: searchPhrase)
                urlComponents.queryItems?.append(queryItem)
            }
        }
        
        return urlComponents.url
    }
}

// MARK: - UICollectionViewDataSource

extension PhotoCollectionViewController {
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return photos.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! PhotoCollectionViewCell
        let photo = photos[indexPath.item]
        let thumbnailURL = photo.urls.small // photo.urls.thumb images are too small
        
        // load image asynchronously, using cached version if it's there
        cell.imageView.loadImageAsync(with: thumbnailURL, completion: nil)
        return cell
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        switch kind {
        case UICollectionElementKindSectionHeader:
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: sectionHeaderIdentifier, for: indexPath as IndexPath) as! CollectionReusableSearchView
            headerView.searchBar.delegate = self
            headerView.searchBar.becomeFirstResponder() // TODO: does this being called more than once cause problems?
            return headerView
        default:
            preconditionFailure("Invalid UICollectionElementKind for this collection view")
        }
    }
}

// MARK: - UICollectionViewDelegate

extension PhotoCollectionViewController {
    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // load more photos when scrolling to the last cell
        let indexOfLastPhoto = photos.count - 1
        if indexPath.item == indexOfLastPhoto {
            // don't attempt to load more search results if the end has been reached
            if collectionType == .search,
                pageNumber == currentSearchTotalPages {
                print("do NOT load more photos... reached last page of search results")
                return
            }
            
            pageNumber += 1
            loadPhotos()
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let photo = photos[indexPath.item]
        delegate?.unsplashPickerControllerDidFinishPicking(photo: photo)
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension PhotoCollectionViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        var cellWidth: CGFloat = 0
        var columns: CGFloat = 1
        
        if currentLayoutStyle == .grid {
            // TODO: add more columns for iPad presented full screen?
            
            // needed if the unsplashPicker is presented without:
            // unsplashPicker.modalPresentationStyle = .popover
            let portraitWidthOfPlusSizePhones: CGFloat = 414.0
            if view.bounds.size.width > portraitWidthOfPlusSizePhones {
                columns = 4
            } else {
                columns = 2
            }
        }
        
        cellWidth = (self.view.bounds.size.width - cellSpacing * (columns - 1)) / columns
        
        switch currentLayoutStyle {
        case .stacked:
            let photo = photos[indexPath.item]
            let scale = cellWidth / photo.size.width
            let cellHeight = photo.size.height * scale
            return CGSize(width: cellWidth, height: cellHeight)
        case .grid:
            return CGSize(width: cellWidth, height: cellWidth)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return cellSpacing
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return cellSpacing
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        if collectionType == .search {
            return CGSize(width: view.bounds.width, height: searchBarHeight)
        } else {
            return CGSize.zero
        }
    }
}
