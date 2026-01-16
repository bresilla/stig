/**
 * @file test_synopsis.hpp
 * @brief Test file for @synopsis command
 */

#pragma once

namespace synopsis_test {

/// @brief Process variadic arguments
/// @synopsis void process(Args... args)
/// @tparam Args Variadic template arguments
/// @param args The arguments to process
template<typename... Args>
void process(Args&&... args);

/// @brief Complex template function with simplified synopsis
/// @synopsis auto transform(Container c, Func f) -> ResultType
/// @tparam Container The container type
/// @tparam Func The transformation function type
/// @param container The input container
/// @param func The transformation function
/// @return The transformed result
template<typename Container, typename Func, 
         typename ResultType = typename std::invoke_result<Func, typename Container::value_type>::type>
auto transform(Container&& container, Func&& func) 
    -> std::vector<ResultType>;

/// @brief Normal function without synopsis override
/// @param x The input value
/// @return The doubled value
int double_value(int x);

/// Using backslash prefix for synopsis
/// \synopsis std::string format(const char* fmt, ...)
/// \brief Format a string with printf-style arguments
/// \param fmt The format string
/// \return The formatted string
template<typename... Args>
std::string format(const char* fmt, Args&&... args);

} // namespace synopsis_test
