REV := 4b279a32dc331dfb8369b33a7fbfa02bf4303919

.PHONY: package
package: ./modest-c/lib/libmodest_static.a

./modest-c:
	git clone https://github.com/lexborisov/Modest.git ./modest-c
	cd modest-c && git reset --hard $(REV)

./modest-c/lib/libmodest_static.a: ./modest-c
	cd modest-c && make static MyHTML_BUILD_SHARED=OFF MyCORE_BUILD_WITHOUT_THREADS=YES PROJECT_OPTIMIZATION_LEVEL=-O3

.PHONY: clean
clean:
	rm -rf modest-c
