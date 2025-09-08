::__index__ <- function(table, key) {
    if (!(key in table))
        return null
    return table[key]
}

::__unpack__ <- function(value) {
    if (typeof value == "array") {
        if (0 in value)
            return value[0]
        else
            return null
    } else {
        throw "ahhh!! no array"
    }

    local return_value = func(args)
}
