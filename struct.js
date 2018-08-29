// a special version of node-struct by xdenser
// https://github.com/xdenser/node-struct/tree/f843487d6768cd0bf20c2ce7803dde2d92df5694

function byteField(p, offset) {
    this.length = 1;
    this.get = function () {
        return p.buf[offset];
    }
    this.set = function (val) {
        p.buf[offset] = val;
    }
}

function boolField(p, offset, length) {
    this.length = length;
    this.get = function () {
        return (p.buf[offset] > 0 );
    }
    this.set = function (val) {
        p.buf[offset] = val ? 1 : 0;
    }
}

function intField(p, offset, length, le, signed) {
    this.length = length;

    function bec(cb) {
        for (var i = 0; i < length; i++)
            cb(i, length - i - 1);
    }

    function lec(cb) {
        for (var i = 0; i < length; i++)
            cb(i, i);
    }

    function getUVal(bor) {
        var val = 0;
        bor(function (i, o) {
            val += Math.pow(256, o) * p.buf[offset + i];
        })
        return val;
    }

    function getSVal(bor) {

        var val = getUVal(bor);
        if ((p.buf[offset + ( le ? (length - 1) : 0)] & 0x80) == 0x80) {
            val -= Math.pow(256, length);
        }
        return val;
    }

    function setVal(bor, val) {
        bor(function (i, o) {
            p.buf[offset + i] = Math.floor(val / Math.pow(256, o)) & 0xff;
        });
    }


    this.get = function () {
        var bor = le ? lec : bec;
        return ( signed ? getSVal(bor) : getUVal(bor));
    }
    this.set = function (val) {
        var bor = le ? lec : bec;
        setVal(bor, val);
    }
}

function charField(p, offset, length, encoding) {
    this.length = length;
    this.encoding = encoding;
    this.get = function () {
        var result = p.buf.toString(this.encoding, offset, offset + length);
        var strlen = result.indexOf("\0");
        if (strlen == -1) {
            return result;
        } else {
            return result.slice(0, strlen);
        }
    }
    this.set = function (val) {
        val += "\0";
        if (val.length > length)
            val = val.substring(0, length);
        p.buf.write(val, offset, this.encoding);
    }
}

function structField(p, offset, struct) {
    this.length = struct.length();
    this.get = function () {
        return struct;
    }
    this.set = function (val) {
        struct.set(val);
    }
    this.allocate = function () {
        struct._setBuff(p.buf.slice(offset, offset + struct.length()));
    }
}

function arrayField(p, offset, len, type) {
    var as = Struct();
    var args = [].slice.call(arguments, 4);
    args.unshift(0);
    for (var i = 0; i < len; i++) {
        if (type instanceof Struct) {
            as.struct(i, type.clone());
        } else if (type in as) {
            args[0] = i;
            as[type].apply(as, args);
        }
    }
    this.length = as.length();
    this.allocate = function () {
        as._setBuff(p.buf.slice(offset, offset + as.length()));
    }
    this.get = function () {
        return as;
    }
    this.set = function (val) {
        as.set(val);
    }
}

function Struct() {
    if (!(this instanceof Struct))
        return new Struct;

    var priv = {
        buf: {},
        allocated: false,
        len: 0,
        fields: {},
        closures: []
    }, self = this;

    function checkAllocated() {
        if (priv.allocated)
            throw new Error('Cant change struct after allocation');
    }


    this.word8 = function (key) {
        checkAllocated();
        priv.closures.push(function (p) {
            p.fields[key] = new byteField(p, p.len);
            p.len++;
        });
        return this;
    };

    // Create handlers for various Bool Field Variants
    [1, 2, 3, 4].forEach(function (n) {
        self['bool' + (n == 1 ? '' : n)] = function (key) {
            checkAllocated();
            priv.closures.push(function (p) {
                p.fields[key] = new boolField(p, p.len, n);
                p.len += n;
            });
            return this;
        }
    });

    // Create handlers for various Integer Field Variants
    [1, 2, 3, 4, 6, 8].forEach(function (n) {
        [true, false].forEach(function (le) {
            [true, false].forEach(function (signed) {
                var name = 'word' + (n * 8) + ( signed ? 'S' : 'U') + ( le ? 'le' : 'be');
                self[name] = function (key) {
                    checkAllocated();
                    priv.closures.push(function (p) {
                        p.fields[key] = new intField(p, p.len, n, le, signed);
                        p.len += n;
                    });
                    return this;
                };
            });
        });
    });

    this.chars = function (key, length, encoding) {
        checkAllocated();
        priv.closures.push(function (p) {
            p.fields[key] = new charField(p, p.len, length, encoding || 'ascii');
            p.len += length;
        });
        return this;
    }

    this.struct = function (key, struct) {
        checkAllocated();
        priv.closures.push(function (p) {
            p.fields[key] = new structField(p, p.len, struct.clone());
            p.len += p.fields[key].length;
        });
        return this;
    }
    function construct(constructor, args) {
        function F() {
            return constructor.apply(this, args);
        }


        F.prototype = constructor.prototype;
        return new F();
    }


    this.array = function (key, length, type) {
        checkAllocated();
        var args = [].slice.call(arguments, 1);
        args.unshift(null);
        args.unshift(null);
        priv.closures.push(function (p) {
            args[0] = p;
            args[1] = p.len;
            p.fields[key] = construct(arrayField, args);
            p.len += p.fields[key].length;
        });

        return this;
    }
    var beenHere = false;

    function applyClosures(p) {
        if (beenHere)
            return;
        p.closures.forEach(function (el) {
            el(p);
        });
        beenHere = true;
    }

    function allocateFields() {
        for (var key in priv.fields) {
            if ('allocate' in priv.fields[key])
                priv.fields[key].allocate();
        }
    }


    this._setBuff = function (buff) {
        priv.buf = buff;
        applyClosures(priv);
        allocateFields();
        priv.allocated = true;
    }

    this.allocate = function () {
        applyClosures(priv);
        priv.buf = Buffer.alloc(priv.len);
        allocateFields();
        priv.allocated = true;
        return this;
    }

    this._getPriv = function () {
        return priv;
    }

    this.clone = function () {
        var c = new Struct;
        var p = c._getPriv();
        p.closures = priv.closures;
        return c;
    }

    this.length = function () {
        applyClosures(priv);
        return priv.len;
    }

    this.get = function (key) {
        if (key in priv.fields) {
            return priv.fields[key].get();
        } else
            throw new Error('Can not find field ' + key);
    }

    this.set = function (key, val) {
        if (arguments.length == 2) {
            if (key in priv.fields) {
                priv.fields[key].set(val);
            } else
                throw new Error('Can not find field ' + key);
        } else if (Buffer.isBuffer(key)) {
            this._setBuff(key);
        } else {
            for (var k in key) {
                this.set(k, key[k]);
            }
        }
    }
    this.buffer = function () {
        return priv.buf;
    }

    function getFields() {
        var fields = {};
        Object.keys(priv.fields).forEach(function (key) {
            Object.defineProperty(fields, key, {
                get: function () {
                    var res = self.get(key);
                    if (res instanceof Struct) return res.fields;
                    else return res;
                },
                set: function (newVal) {
                    self.set(key, newVal);
                },
                enumerable: true
            });
        });
        return fields;
    };

    var _fields;
    Object.defineProperty(this, 'fields', {
        get: function () {
            if (_fields) return _fields;
            return (_fields = getFields());
        },
        enumerable: true,
        configurable: true
    });

}
exports.Struct = Struct;
