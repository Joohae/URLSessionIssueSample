//
//  ViewController.swift
//  VKWebSocketTest
//
//  Created by Joohae  Kim on 10/30/23.
//

import UIKit

class ViewController: UIViewController {
  public var webSocket: VKWebsocket?
  override func viewDidLoad() {
    super.viewDidLoad()

    // Do any additional setup after loading the view.
    let button = UIButton()
    button.layer.borderColor = UIColor.black.cgColor
    button.layer.borderWidth = 1
    button.setTitle("Hit me!", for: .normal)
    button.setTitleColor(.blue, for: .normal)
    button.addTarget(self, action: #selector(didTapButton(_:)), for: .touchUpInside)

    button.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(button)
    view.addConstraints([
      NSLayoutConstraint(item: button, attribute: .centerX, relatedBy: .equal, toItem: view, attribute: .centerX, multiplier: 1, constant: 0),
      NSLayoutConstraint(item: button, attribute: .centerY, relatedBy: .equal, toItem: view, attribute: .centerY, multiplier: 1, constant: 0),
      NSLayoutConstraint(item: button, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .width, multiplier: 1, constant: 200),
      NSLayoutConstraint(item: button, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .height, multiplier: 1, constant: 100),
    ])
  }

  @objc func didTapButton(_ button: UIButton) {
    if webSocket == nil {
      connect()
    } else {
      disconnect()
    }
  }

  private func connect() {
    Task {
      webSocket = VKWebsocket(request: URLRequest(url: URL(string: "wss://socketsbay.com/wss/v2/1/demo/")!))
      await webSocket?.setDelegate(self)
      await webSocket?.connect()
    }
  }

  private func disconnect() {
    Task {
      await webSocket?.disconnect()
    }
  }
}

extension ViewController: WebsocketDelegate {
  func websocket(_ websocket: VKWebsocket, didReceive message: URLSessionWebSocketTask.Message) {
    print("\(#function): \(message)")
  }

  func websocket(_ websocket: VKWebsocket, didError error: Error?) {
    if error != nil {
      print("\(#function): \(String(describing: error))")
    } else {
      print("\(#function): the message has been sent")
    }
  }

  func websocket(_ websocket: VKWebsocket, didChange connectionState: VKWebsocket.ConnectionState) {
    Task {
      print("\(#function): \(connectionState)")
      switch connectionState {
      case .connected:
        let message = "Have a good day!"
        print("Connected, and seinding message '\(message)'")
        await websocket.sendMessage(message: .string(message))
      case .connecting:
        print("Connecting...")
      case .disconnected:
        print("Disconnected!")
        self.webSocket = nil
      }
    }
  }
}

