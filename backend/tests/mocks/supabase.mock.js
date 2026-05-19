'use strict';

/**
 * Mock Supabase client cho integration tests.
 *
 * Mỗi test gọi __setSelectResult / __setInsertResult / __setUpdateResult
 * để kiểm soát giá trị trả về. Chainable builder pattern giống Supabase JS SDK.
 */

let _selectResult  = null;
let _insertResult  = null;
let _updateResult  = null;
let _deleteResult  = null;
let _selectError   = null;
let _callCount     = 0;

// Multiple sequential results: mỗi lần gọi .single()/.maybeSingle() trả một giá trị khác nhau
let _selectQueue = [];

function __reset() {
  _selectResult = null;
  _insertResult = null;
  _updateResult = null;
  _deleteResult = null;
  _selectError  = null;
  _callCount    = 0;
  _selectQueue  = [];
}

function __setSelectResult(data, error = null) {
  _selectResult = data;
  _selectError  = error;
}

function __setSelectQueue(...items) {
  _selectQueue = [...items];
}

function __setInsertResult(data, error = null) {
  _insertResult = { data, error };
}

function __setUpdateResult(data, error = null) {
  _updateResult = { data, error };
}

function __setDeleteResult(error = null) {
  _deleteResult = { error };
}

// ── Builder ───────────────────────────────────────────────────────────────────

function makeBuilder(type = 'select') {
  const builder = {
    select:        () => makeBuilder(type === 'select' ? 'select' : type), // preserve insert/update type
    insert:        () => makeBuilder('insert'),
    update:        () => makeBuilder('update'),
    upsert:        () => makeBuilder('upsert'),
    delete:        () => makeBuilder('delete'),
    eq:            () => builder,
    neq:           () => builder,
    gt:            () => builder,
    lt:            () => builder,
    gte:           () => builder,
    lte:           () => builder,
    in:            () => builder,
    order:         () => builder,
    limit:         () => builder,
    range:         () => builder,
    match:         () => builder,
    filter:        () => builder,
    is:            () => builder,
    not:           () => builder,
    or:            () => builder,
    textSearch:    () => builder,
    contains:      () => builder,
    overlaps:      () => builder,

    // Terminal methods
    single: async () => {
      if (type === 'insert') {
        const r = _insertResult || { data: null, error: null };
        return { data: r.data, error: r.error };
      }
      if (type === 'update' || type === 'upsert') {
        const r = _updateResult || { data: null, error: null };
        return { data: r.data, error: r.error };
      }
      // select queue (multi-call)
      if (_selectQueue.length > 0) {
        const next = _selectQueue.shift();
        return { data: next, error: null };
      }
      return { data: _selectResult, error: _selectError };
    },

    maybeSingle: async () => {
      if (_selectQueue.length > 0) {
        const next = _selectQueue.shift();
        return { data: next, error: null };
      }
      return { data: _selectResult, error: _selectError };
    },

    // Promise-like untuk query tanpa .single()
    then: (resolve) => {
      if (type === 'delete') {
        const r = _deleteResult || { error: null };
        return Promise.resolve({ data: null, error: r.error }).then(resolve);
      }
      if (type === 'insert' || type === 'upsert') {
        const r = _insertResult || { data: null, error: null };
        return Promise.resolve({ data: r.data ? [r.data] : [], error: r.error, count: r.data ? 1 : 0 }).then(resolve);
      }
      if (type === 'update') {
        const r = _updateResult || { data: null, error: null };
        return Promise.resolve({ data: r.data ? [r.data] : [], error: r.error }).then(resolve);
      }
      // select list
      const data = _selectResult !== null ? [_selectResult] : [];
      return Promise.resolve({ data, error: _selectError, count: data.length }).then(resolve);
    },
  };
  return builder;
}

// ── Client ────────────────────────────────────────────────────────────────────

const supabase = {
  from: () => makeBuilder('select'),
  rpc:  () => Promise.resolve({ data: null, error: null }),

  // expose test helpers
  __reset,
  __setSelectResult,
  __setSelectQueue,
  __setInsertResult,
  __setUpdateResult,
  __setDeleteResult,
};

module.exports = supabase;
