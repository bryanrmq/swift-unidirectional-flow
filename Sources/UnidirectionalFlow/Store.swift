//
//  Store.swift
//  UnidirectionalFlow
//
//  Created by Majid Jabrayilov on 11.06.22.
//
import Observation

// MARK: - Store

/// Type that stores the state of the app or feature.
@dynamicMemberLookup
public final class Store<State, Action>: ObservableObject {

  // MARK: Lifecycle

  /// Creates an instance of `Store` with the folowing parameters.
  public init(
    initialState state: State,
    reducer: some Reducer<State, Action>,
    middlewares: some Collection<any Middleware<State, Action>>) {
    self.state = state
    self.reducer = reducer
    self.middlewares = middlewares
  }

  // MARK: Public

  /// A subscript providing access to the state of the store.
  public subscript<T>(dynamicMember keyPath: KeyPath<State, T>) -> T {
    lock.withLock { state[keyPath: keyPath] }
  }

  /// Use this method to mutate the state of the store by feeding actions.
  @MainActor
  public func send(_ action: Action) async {
    let newState = lock.withLock {
      state = reducer.reduce(oldState: state, with: action)
      return state
    }

    await withTaskGroup(of: Action?.self) { group in
      middlewares.forEach { middleware in
        group.addTask {
          await middleware.process(state: newState, with: action)
        }
      }

      for await case let nextAction? in group {
        await send(nextAction)
      }
    }
  }

  // MARK: Internal

  @Published var state: State

  // MARK: Private

  private let reducer: any Reducer<State, Action>
  private let middlewares: any Collection<any Middleware<State, Action>>
  private let lock = NSRecursiveLock()

}

import SwiftUI

extension Store {
  /// Use this method to create a `SwiftUI.Binding` from any instance of `Store`.
  public func binding<Value>(
    extract: @escaping (State) -> Value,
    embed: @escaping (Value) -> Action) -> Binding<Value> {
    .init(
      get: { self.lock.withLock { extract(self.state) } },
      set: { newValue in Task { await self.send(embed(newValue)) } })
  }
}
